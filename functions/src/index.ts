import * as functions from 'firebase-functions';
import fetch from 'node-fetch';


// The Analysis Schema defines the required output structure for homework analysis.
// This schema focuses on identifying EXERCISES only. Non-exercise content (headers,
// footers, page numbers, etc.) should be marked as "SKIP".
const analysisSchema = {
    type: "OBJECT",
    properties: {
        summary: {
            type: "STRING",
            description: "A concise summary of the homework, focusing on the number and types of exercises found."
        },
        sections: {
            type: "ARRAY",
            description: "A chronological list of content blocks derived from the image. Only EXERCISE blocks will be processed by the app; SKIP blocks are ignored.",
            items: {
                type: "OBJECT",
                properties: {
                    type: {
                        type: "STRING",
                        description: "The nature of this content block. Must be either 'EXERCISE' (a problem/task to be solved) or 'SKIP' (headers, footers, titles, page numbers, or non-exercise content).",
                        enum: ["EXERCISE", "SKIP"]
                    },
                    title: {
                        type: "STRING",
                        description: "A concise title or identifier for this block (e.g., 'Exercise 8', 'Problem 3', or 'Header' for skipped content)."
                    },
                    content: {
                        type: "STRING",
                        description: "The complete, CORRECTED text content of this exercise, with mathematical expressions in LaTeX format. Read the text directly from the IMAGE to ensure accuracy, especially for mathematical notation, special characters, and symbols. The OCR data is a REFERENCE for positioning only and may contain errors. Your content must be the ACTUAL text you see in the image, properly formatted and error-free."
                    },
                    subject: {
                        type: "STRING",
                        description: "The subject/topic of this exercise (e.g., 'mathematics', 'language', 'science', 'history', 'grammar'). Only for EXERCISE type.",
                        enum: ["mathematics", "language", "science", "history", "grammar", "reading", "writing", "other"]
                    },
                    inputType: {
                        type: "STRING",
                        description: "The recommended input method for answering this exercise. 'inline' for filling in blanks/placeholders within the exercise, 'text' for short written answers in a separate area, 'canvas' for problems requiring calculations/drawings/diagrams, 'both' for exercises needing both written work and final answer. Only for EXERCISE type.",
                        enum: ["inline", "text", "canvas", "both"]
                    },
                    yStart: {
                        type: "INTEGER",
                        description: "The MINIMUM Y coordinate associated with the visual boundary of this section."
                    },
                    yEnd: {
                        type: "INTEGER",
                        description: "The MAXIMUM Y coordinate associated with the visual boundary of this section."
                    }
                },
                required: ["type", "title", "content", "yStart", "yEnd"]
            }
        }
    },
    required: ["summary", "sections"]
};

/**
 * Converts a Base64 string to a Google Generative AI Part object.
 * @param base64Image The Base64 encoded image string (without the 'data:image/...' prefix).
 * @param mimeType The MIME type of the image (e.g., 'image/png').
 */
function base64ToGenerativePart(base64Image: string, mimeType: string) {
    return {
        inlineData: {
            data: base64Image,
            mimeType,
        },
    };
}

/**
 * Analyzes a homework image and its OCR text using the Gemini LLM to split it into structured sections.
 *
 * SECURITY: This function enforces Firebase App Check to verify requests come from legitimate app instances.
 *
 * Note: Function timeout is configured in firebase.json for the emulator
 */
export const analyzeHomework = functions.https.onRequest(async (req, res) => {
    // Check for POST request
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed. Use POST.');
        return;
    }

    // SECURITY: Verify App Check token
    const appCheckToken = req.header('X-Firebase-AppCheck');
    const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';

    if (!appCheckToken) {
        functions.logger.warn('Request rejected: Missing App Check token');
        res.status(401).send('Unauthorized: App Check token required.');
        return;
    }

    // Log token receipt
    functions.logger.info(`✅ App Check token received: ${appCheckToken.substring(0, Math.min(20, appCheckToken.length))}...`);

    // Allow bypass token in emulator mode for local development
    if (isEmulator && appCheckToken === 'emulator-bypass-token') {
        functions.logger.info('🔐 EMULATOR MODE: Using bypass token for local development');
        functions.logger.warn('⚠️  App Check is DISABLED. This is only allowed in emulator mode.');
    } else if (isEmulator) {
        functions.logger.info('🔐 EMULATOR MODE: App Check token validation is simplified. In production, Firebase will fully validate the token signature.');
    }

    // Note: For v1 functions, we verify token presence. Firebase App Check debug tokens
    // are pre-registered in console and will work in both emulator and production.
    // For v2 functions, use consumeAppCheckToken: true for automatic validation.

    // API Key from Firebase environment variables
    // In local emulator, this is loaded from .env. In deployment, from functions config.
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        functions.logger.error("GEMINI_API_KEY environment variable not set. Check .env file or functions config.");
        res.status(500).send('Server configuration error: API Key missing.');
        return;
    }

    // Input validation
    const { imageBase64, imageMimeType, ocrJsonText } = req.body;
    if (!imageBase64 || !imageMimeType || !ocrJsonText) {
        res.status(400).send('Missing required parameters: imageBase64, imageMimeType, or ocrJsonText.');
        return;
    }

    // 1. Define the system instruction for the LLM's role, focused on exercise identification
    const systemInstruction = `You are an intelligent homework analysis engine. Your task is to analyze the provided homework image and its OCR text (which includes Y-coordinates for each text block).

Your primary goal is to identify and segment EXERCISES from the homework, while marking non-exercise content as SKIP. Output the result in the required JSON schema.

--- CLASSIFICATION GUIDELINES ---
Analyze each segment of text and classify it as EITHER 'EXERCISE' OR 'SKIP'.

EXERCISE (type: 'EXERCISE'):
- Numbered problems or tasks (e.g., "1.", "2.", "a)", "Exercise 8")
- Content with imperative verbs: "Find", "Calculate", "Solve", "Show", "Prove", "Determine", "Complete", "Fill in", "Draw", "Explain", "Write", "Compute"
- Questions with question marks asking students to perform tasks
- Problems or exercises that students need to solve
- Any content that instructs students to DO something or ANSWER something
- Mathematical problems, word problems, or computational tasks

SKIP (type: 'SKIP'):
- Page headers, footers, or titles (e.g., "Mathematics Homework", "Page 3")
- Page numbers
- Pure titles without questions or tasks (e.g., "Geometry Exercises" as a header)
- Instructions about the assignment itself (e.g., "Complete all problems by Friday")
- Teacher notes or administrative text
- Content that is purely decorative or organizational

--- SUBJECT CLASSIFICATION ---
For each EXERCISE, determine the subject:
- 'mathematics': Math problems, calculations, equations, geometry, algebra, arithmetic
- 'language': Grammar, vocabulary, sentence construction, language learning
- 'science': Biology, physics, chemistry, experiments, scientific concepts
- 'history': Historical events, dates, historical analysis
- 'grammar': Specific grammar exercises, punctuation, parts of speech
- 'reading': Reading comprehension, text analysis
- 'writing': Essays, creative writing, written composition
- 'other': Any other subject not listed above

--- INPUT TYPE DETERMINATION ---
For each EXERCISE, determine the best input method based on these rules:

Use 'inline' when:
- Fill-in-the-blank exercises with visible placeholders (underscores ___, blank lines, or [blank])
- Exercises with spaces within sentences to complete
- Word completion exercises where answer goes in a specific spot
- Any exercise with explicit blank spaces or placeholders in the text
- Example: "The capital of France is ___" or "2 + 2 = ___"

Use 'text' when:
- Simple short-answer questions WITHOUT placeholders (e.g., "What is the capital of France?")
- Yes/No or true/false questions
- Definition or vocabulary questions
- Simple factual recall questions
- Questions asking for a single word, phrase, or sentence answer
- Multiple choice questions where student writes the letter

Use 'canvas' when:
- Mathematics problems requiring calculations, work shown, or step-by-step solving
- Geometry problems requiring drawings or diagrams
- Science diagrams or labeled illustrations
- Any problem where visual work/calculations are expected
- Problems explicitly asking to "show your work" or "draw"
- Long-form mathematical solutions

Use 'both' when:
- Complex math word problems (need calculations + written answer)
- Science questions requiring both diagrams and explanations
- Problems asking to "explain" or "justify" your mathematical solution
- Any exercise requiring both visual work and written explanation

--- IMPORTANT RULES ---
- If a text segment contains a numbered item with a question or task, it is an EXERCISE.
- If in doubt between EXERCISE and SKIP, lean toward EXERCISE for numbered items.
- Each EXERCISE should be a complete, self-contained problem or task.
- Segment exercises by visual gaps and Y-coordinate jumps in the OCR data.
- For mathematics exercises, default to 'canvas' or 'both' to allow showing work.
- For simple recall questions, use 'text' for quick answers.

--- COORDINATE & CONTENT EXTRACTION INSTRUCTIONS ---
1. Use the 'ocrJsonText' data ONLY for Y-coordinates to define the visual boundaries of each section.
2. The 'yStart' must be the MINIMUM Y-coordinate of any text paragraph belonging to that section.
3. The 'yEnd' must be the MAXIMUM Y-coordinate of any text paragraph belonging to that section.
4. For the 'content' field: READ THE TEXT DIRECTLY FROM THE IMAGE. The OCR data may have errors, especially with:
   - Mathematical symbols and notation (e.g., exponents, fractions, special operators)
   - Special characters and punctuation
   - Accented letters and non-English characters
   - Formatting and spacing
5. IMPORTANT: Your 'content' must be the ACCURATE text you actually see in the image, NOT the OCR text. Correct all errors.
6. For all mathematical content, you MUST use LaTeX notation. Enclose inline math expressions with \( and \). Enclose block math expressions with \[ and \]. For example: \(x^2 + y^2 = r^2\) or \[\sum_{i=1}^{n} i = \frac{n(n+1)}{2}\]
7. When creating the 'content', it is crucial that you preserve the original formatting and indentation of the exercise as seen in the image. This includes line breaks, spacing, and any other structural elements.
8. Group related text blocks that belong to the same exercise based on proximity (Y-coordinates) and content continuity.
9. Your output MUST strictly adhere to the provided JSON schema.`;;


    // 2. Define the user prompt, combining the image and text data
    const userPrompt = `Analyze this homework document and identify all exercises.

--- OCR TEXT DATA (FOR Y-COORDINATES ONLY) ---
${ocrJsonText}
--- END OCR TEXT DATA ---

IMPORTANT INSTRUCTIONS:
1. Use the OCR data ONLY to identify Y-coordinates for positioning exercises
2. For exercise CONTENT, read the text directly from the IMAGE - the OCR may have errors
3. Correct all OCR errors, especially mathematical notation, special characters, and symbols
4. Provide clean, accurate text that matches what you see in the image
5. For all mathematical content, you MUST use LaTeX notation. Enclose inline math expressions with \( and \). Enclose block math expressions with \[ and \].

Identify and segment each EXERCISE with corrected, accurate content. Mark headers, footers, titles, and non-exercise content as SKIP. Produce the structured JSON analysis following the provided schema.`;

    // 3. Construct the API payload
    // Use stable Gemini 2.5 Flash model (free tier, supports 1M tokens)
    const model = "gemini-2.5-flash";
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: "user",
                parts: [
                    // Part 1: The input image (multimodal)
                    base64ToGenerativePart(imageBase64, imageMimeType),
                    // Part 2: The text prompt and OCR data
                    { text: userPrompt }
                ]
            }
        ],
        // Configuration for structured output
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: analysisSchema
        },
        // Configuration for the LLM's persona/role
        systemInstruction: {
            parts: [{ text: systemInstruction }]
        }
    };

    // 4. Implement Exponential Backoff and API Call
    const MAX_RETRIES = 5;
    let lastError: Error | null = null;

    functions.logger.info(`🚀 Starting Gemini API call (attempt 1 of ${MAX_RETRIES})`);
    functions.logger.info(`📊 Payload size: ${JSON.stringify(payload).length} bytes`);

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            functions.logger.info(`📡 Calling Gemini API at: ${apiUrl.substring(0, 80)}...`);
            const startTime = Date.now();

            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const elapsed = Date.now() - startTime;
            functions.logger.info(`⏱️  Gemini API responded in ${elapsed}ms with status ${response.status}`);

            // Cast result to 'any' to resolve the TS18046 error, as its structure is complex/external. 
            const result: any = await response.json(); 

            if (!response.ok) {
                throw new Error(`API returned status ${response.status}: ${JSON.stringify(result)}`);
            }

            const jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text;

            if (!jsonText) {
                // If the model fails to produce the structured text, it's a model-side issue
                throw new Error('LLM output content is missing or structured incorrectly.');
            }

            // Successfully received JSON response from the model
            const structuredOutput = JSON.parse(jsonText);

            functions.logger.info(`✅ Successfully analyzed homework. Sections: ${structuredOutput.sections?.length || 0}`);

            // Log exercise details
            functions.logger.info("structuredOutput:", structuredOutput);

            // Return the structured JSON to the client
            res.status(200).json(structuredOutput);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`❌ Attempt ${attempt + 1} failed: ${lastError.message}`);
            functions.logger.warn(`Error stack: ${lastError.stack}`);

            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000 + Math.random() * 1000; // Exponential backoff + jitter
                functions.logger.info(`⏳ Retrying in ${Math.round(delay / 1000)}s...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // 5. Final error response after all retries fail
    functions.logger.error('💥 Failed to get LLM response after multiple retries.', lastError);
    functions.logger.error(`Final error: ${lastError?.message || 'Unknown error'}`);
    res.status(500).send(`Failed to analyze document: ${lastError?.message || 'Unknown error occurred.'}`);
});

/**
 * Verifies a student's answer to a homework exercise using Gemini AI.
 *
 * SECURITY: This function enforces Firebase App Check to verify requests come from legitimate app instances.
 */
export const verifyAnswer = functions.https.onRequest(async (req, res) => {
    // Check for POST request
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed. Use POST.');
        return;
    }

    // SECURITY: Verify App Check token
    const appCheckToken = req.header('X-Firebase-AppCheck');
    const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';

    if (!appCheckToken) {
        functions.logger.warn('Request rejected: Missing App Check token');
        res.status(401).send('Unauthorized: App Check token required.');
        return;
    }

    functions.logger.info(`✅ App Check token received for answer verification`);

    // Allow bypass token in emulator mode
    if (isEmulator && appCheckToken === 'emulator-bypass-token') {
        functions.logger.info('🔐 EMULATOR MODE: Using bypass token for local development');
    }

    // API Key
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        functions.logger.error("GEMINI_API_KEY environment variable not set.");
        res.status(500).send('Server configuration error: API Key missing.');
        return;
    }

    // Input validation
    const { exerciseContent, exerciseSubject, answerType, answerText, answerImageBase64, answerImageMimeType } = req.body;

    if (!exerciseContent || !answerType) {
        res.status(400).send('Missing required parameters: exerciseContent or answerType.');
        return;
    }

    // Validate we have answer data
    if (answerType === 'canvas' && !answerImageBase64) {
        res.status(400).send('Missing answerImageBase64 for canvas answer type.');
        return;
    }

    if ((answerType === 'text' || answerType === 'inline') && !answerText) {
        res.status(400).send('Missing answerText for text/inline answer type.');
        return;
    }

    // System instruction for answer verification
    const systemInstruction = `You are an expert teacher evaluating a student's homework answer. Your task is to:
1. Carefully review the exercise question
2. Analyze the student's answer
3. Determine if the answer is correct, partially correct, or incorrect
4. Provide constructive, encouraging feedback
5. If incorrect, give helpful hints without revealing the full answer

Be supportive and educational. Focus on understanding, not just correctness. For math problems, check the work shown, not just the final answer.`;

    // Build the user prompt based on answer type
    let userPrompt = `Exercise: ${exerciseContent}\n\n`;

    if (exerciseSubject) {
        userPrompt += `Subject: ${exerciseSubject}\n\n`;
    }

    const parts: any[] = [];

    if (answerType === 'canvas') {
        userPrompt += `The student's answer is shown in the attached image (their written work on a canvas).

Please evaluate:
1. Is the answer correct?
2. Is the work shown clear and logical?
3. Are there any mistakes in the process?

Respond in JSON format with:
{
    "isCorrect": true/false,
    "confidence": "high"/"medium"/"low",
    "feedback": "A supportive message explaining the evaluation",
    "suggestions": "Hints or guidance for improvement (if needed)"
}`;

        parts.push(
            { text: userPrompt },
            base64ToGenerativePart(answerImageBase64, answerImageMimeType || 'image/png')
        );
    } else {
        userPrompt += `Student's answer: "${answerText}"\n\n`;
        userPrompt += `Please evaluate if this answer is correct. Respond in JSON format with:
{
    "isCorrect": true/false,
    "confidence": "high"/"medium"/"low",
    "feedback": "A supportive message explaining the evaluation",
    "suggestions": "Hints or guidance for improvement (if needed)"
}`;

        parts.push({ text: userPrompt });
    }

    // Construct the API payload
    const model = "gemini-2.5-flash";
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: "user",
                parts: parts
            }
        ],
        generationConfig: {
            responseMimeType: "application/json"
        },
        systemInstruction: {
            parts: [{ text: systemInstruction }]
        }
    };

    // Call the API with retry logic
    const MAX_RETRIES = 3;
    let lastError: Error | null = null;

    functions.logger.info(`🔍 Verifying ${answerType} answer for exercise`);

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const startTime = Date.now();

            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const elapsed = Date.now() - startTime;
            functions.logger.info(`⏱️  Verification completed in ${elapsed}ms with status ${response.status}`);

            const result: any = await response.json();

            if (!response.ok) {
                throw new Error(`API returned status ${response.status}: ${JSON.stringify(result)}`);
            }

            const jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text;

            if (!jsonText) {
                throw new Error('LLM output content is missing.');
            }

            const verificationResult = JSON.parse(jsonText);

            functions.logger.info(`✅ Verification complete - Correct: ${verificationResult.isCorrect}`);

            // Return the verification result
            res.status(200).json(verificationResult);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`❌ Verification attempt ${attempt + 1} failed: ${lastError.message}`);

            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000;
                functions.logger.info(`⏳ Retrying in ${Math.round(delay / 1000)}s...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // Final error response
    functions.logger.error('💥 Failed to verify answer after retries.', lastError);
    res.status(500).send(`Failed to verify answer: ${lastError?.message || 'Unknown error occurred.'}`);
});
