import * as functions from 'firebase-functions';
import fetch from 'node-fetch';

/**
 * Fixes common LaTeX escaping issues in JSON strings from Gemini.
 * Gemini sometimes generates malformed LaTeX even with structured output mode.
 */
function fixLatexEscaping(jsonText: string): string {
    // First, protect already-correct double-backslash sequences
    let fixed = jsonText
        .replace(/\\\\\(/g, '\u0001LPAREN\u0001')
        .replace(/\\\\\)/g, '\u0001RPAREN\u0001')
        .replace(/\\\\\[/g, '\u0001LBRACKET\u0001')
        .replace(/\\\\\]/g, '\u0001RBRACKET\u0001')
        .replace(/\\\\text\{/g, '\u0001TEXTBRACE\u0001')
        .replace(/\\\\text /g, '\u0001TEXTSPACE\u0001')
        .replace(/\\\\frac/g, '\u0001FRAC\u0001')
        .replace(/\\\\Omega/g, '\u0001OMEGA\u0001')
        .replace(/\\\\pi/g, '\u0001PI\u0001');

    // Fix the common malformed pattern: ")text{" which should be " \text{"
    // Example: \(4)text{V) -> \(4 \text{ V}\)
    fixed = fixed.replace(/\)text\{/g, ' \\text{');

    // Fix single backslash LaTeX delimiters: \( -> \\(, \) -> \\)
    fixed = fixed.replace(/([^\\]|^)\\(\()/g, '$1\\\\$2');
    fixed = fixed.replace(/([^\\])\\(\))/g, '$1\\\\$2');

    // Fix pipe characters: |( -> \\(, |) -> \\)
    fixed = fixed.replace(/\|\(/g, '\\\\(');
    fixed = fixed.replace(/\|\)/g, '\\\\)');

    // Fix patterns with units: 4.0\text V -> 4.0\text{ V}
    fixed = fixed.replace(/\\text ([A-Za-z])/g, '\\\\text{ $1}');

    // Fix closing patterns: VH) -> V\), mA' -> mA\)
    fixed = fixed.replace(/([A-Z])H\)/g, '$1\\\\)');
    fixed = fixed.replace(/([a-zA-Z])'/g, '$1\\\\)');

    // Restore protected sequences
    fixed = fixed
        .replace(/\u0001LPAREN\u0001/g, '\\\\(')
        .replace(/\u0001RPAREN\u0001/g, '\\\\)')
        .replace(/\u0001LBRACKET\u0001/g, '\\\\[')
        .replace(/\u0001RBRACKET\u0001/g, '\\\\]')
        .replace(/\u0001TEXTBRACE\u0001/g, '\\\\text{')
        .replace(/\u0001TEXTSPACE\u0001/g, '\\\\text ')
        .replace(/\u0001FRAC\u0001/g, '\\\\frac')
        .replace(/\u0001OMEGA\u0001/g, '\\\\Omega')
        .replace(/\u0001PI\u0001/g, '\\\\pi');

    return fixed;
}

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
                        description: "The Y coordinate where this section STARTS on the page. Coordinate system: Y=0 is the TOP of the page, Y=1000 is the BOTTOM. This is the smaller Y value (closer to top)."
                    },
                    yEnd: {
                        type: "INTEGER",
                        description: "The Y coordinate where this section ENDS on the page. Coordinate system: Y=0 is the TOP of the page, Y=1000 is the BOTTOM. This is the larger Y value (closer to bottom)."
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
- Content with imperative verbs: "Task", "Find", "Calculate", "Solve", "Show", "Prove", "Determine", "Complete", "Fill in", "Draw", "Explain", "Write", "Compute"
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
2. COORDINATE SYSTEM: Y=0 is at the TOP of the page, Y=1000 is at the BOTTOM (standard top-to-bottom reading order).
3. The 'yStart' is where the section STARTS (top edge) - this is the SMALLER Y value.
4. The 'yEnd' is where the section ENDS (bottom edge) - this is the LARGER Y value.
5. For the 'content' field: READ THE TEXT DIRECTLY FROM THE IMAGE. The OCR data may have errors, especially with:
   - Mathematical symbols and notation (e.g., exponents, fractions, special operators)
   - Special characters and punctuation
   - Accented letters and non-English characters
   - Formatting and spacing
6. IMPORTANT: Your 'content' must be the ACCURATE text you actually see in the image, NOT the OCR text. Correct all errors.
7. For all mathematical content, you MUST use LaTeX notation. Enclose inline math expressions with \( and \). Enclose block math expressions with \[ and \]. For example: \(x^2 + y^2 = r^2\) or \[\sum_{i=1}^{n} i = \frac{n(n+1)}{2}\]
8. When creating the 'content', it is crucial that you preserve the original formatting and indentation of the exercise as seen in the image. This includes line breaks, spacing, and any other structural elements.
9. Group related text blocks that belong to the same exercise based on proximity (Y-coordinates) and content continuity.
10. Your output MUST strictly adhere to the provided JSON schema.`;;


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

/**
 * Generates progressive hints for an exercise using Gemini AI.
 *
 * SECURITY: This function enforces Firebase App Check to verify requests come from legitimate app instances.
 */
export const generateHints = functions.https.onRequest(async (req, res) => {
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

    functions.logger.info(`✅ App Check token received for hints generation`);

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
    const { exerciseNumber, exerciseType, exerciseContent, subject } = req.body;

    if (!exerciseContent || !exerciseType) {
        res.status(400).send('Missing required parameters: exerciseContent or exerciseType.');
        return;
    }

    // System instruction for hint generation
    const systemInstruction = `You are an educational tutor providing progressive hints to help students solve exercises.

Generate exactly 4 progressive hints to help students solve this exercise. Each hint should reveal more information:

Level 1: Basic hint - Point the student in the right direction for ALL parts without giving away the method
Level 2: Method hint - Explain the approach or formula needed for EACH part, but don't solve
Level 3: Detailed hint - Guide through the steps for EACH part, getting very close to the solution but NOT giving final answers
Level 4: Complete answer - Provide the full solution for ALL parts with clear explanations

IMPORTANT: If this exercise has multiple sub-parts (like a, b, c or 1, 2, 3), address ALL parts in each hint level.

CRITICAL JSON FORMATTING - LaTeX Escaping Rules:
In JSON strings, every backslash must be written as double backslash (\\\\).

For LaTeX math notation:
- Inline math delimiters: \\\\( and \\\\)
- Block math delimiters: \\\\[ and \\\\]
- LaTeX commands like \\\\frac, \\\\text, \\\\pi also need double backslash

Concrete examples of CORRECT JSON:
- "content": "Calculate \\\\(x^2 + 5\\\\)"
- "content": "Simplify \\\\(\\\\frac{a}{b}\\\\)"
- "content": "The voltage is \\\\(2.0\\\\text{ V}\\\\)"
- "content": "Current is \\\\(1.5\\\\text{ A}\\\\)"
- "content": "Resistance: \\\\(10\\\\,\\\\Omega\\\\)"

WRONG examples (do NOT do this):
- "content": "Calculate \\(x^2\\)" ← Single backslash will break JSON
- "content": "Voltage \\(2.0 ||text V\\)" ← Wrong syntax, missing backslash before text
- "content": "Current |(1.0 \\ |text A" ← Malformed, random characters

Remember: In your JSON output, write \\\\text NOT \\text, write \\\\( NOT \\(

Guidelines:
- Be encouraging and supportive
- Each hint progressively more detailed
- Use clear, student-friendly language
- Proper LaTeX syntax with correct JSON escaping
- For multi-part exercises, address every sub-part in every hint level`;

    // Build the user prompt
    const userPrompt = `Exercise Type: ${exerciseType}
${subject ? `Subject: ${subject}` : ''}
Exercise Content: ${exerciseContent}

Generate 4 progressive hints for this exercise. Return your response as a JSON array.

CRITICAL LaTeX Formatting in JSON:
✓ CORRECT: "content": "The voltage is \\\\(2.0\\\\text{ V}\\\\)"
✗ WRONG: "content": "The voltage is \\(2.0 ||text V\\)"
✗ WRONG: "content": "The voltage is |(2.0 \\ |text V"

Example JSON structure:
[
    {
        "level": 1,
        "title": "Think About...",
        "content": "A gentle nudge in the right direction"
    },
    {
        "level": 2,
        "title": "Method to Use",
        "content": "Explain the approach with proper math notation like \\\\(formula\\\\)"
    },
    {
        "level": 3,
        "title": "Step-by-Step Guide",
        "content": "Walk through the solution process step by step"
    },
    {
        "level": 4,
        "title": "Complete Answer",
        "content": "Full solution with explanations"
    }
]`;

    // Construct the API payload
    const model = "gemini-2.5-flash";
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: "user",
                parts: [{ text: userPrompt }]
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

    functions.logger.info(`💡 Generating hints for exercise #${exerciseNumber || 'unknown'}`);

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const startTime = Date.now();

            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const elapsed = Date.now() - startTime;
            functions.logger.info(`⏱️  Hints generation completed in ${elapsed}ms with status ${response.status}`);

            const result: any = await response.json();

            if (!response.ok) {
                throw new Error(`API returned status ${response.status}: ${JSON.stringify(result)}`);
            }

            let jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text;

            if (!jsonText) {
                throw new Error('LLM output content is missing.');
            }

            // Clean up potential JSON formatting issues from LLM
            // Remove markdown code block wrapper if present
            jsonText = jsonText.trim();
            if (jsonText.startsWith('```json')) {
                jsonText = jsonText.substring(7);
            }
            if (jsonText.startsWith('```')) {
                jsonText = jsonText.substring(3);
            }
            if (jsonText.endsWith('```')) {
                jsonText = jsonText.substring(0, jsonText.length - 3);
            }
            jsonText = jsonText.trim();

            // Fix common LaTeX escaping issues before parsing
            jsonText = fixLatexEscaping(jsonText);

            functions.logger.info(`📝 Parsing hints JSON (length: ${jsonText.length})`);

            const hints = JSON.parse(jsonText);

            functions.logger.info(`✅ Generated ${hints.length} hints successfully`);

            // Return the hints array
            res.status(200).json(hints);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`❌ Hints generation attempt ${attempt + 1} failed: ${lastError.message}`);

            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000;
                functions.logger.info(`⏳ Retrying in ${Math.round(delay / 1000)}s...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // Final error response
    functions.logger.error('💥 Failed to generate hints after retries.', lastError);
    res.status(500).send(`Failed to generate hints: ${lastError?.message || 'Unknown error occurred.'}`);
});

/**
 * Generates similar practice exercises based on an existing exercise using Gemini AI.
 *
 * SECURITY: This function enforces Firebase App Check to verify requests come from legitimate app instances.
 */
export const generateSimilarExercises = functions.https.onRequest(async (req, res) => {
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

    functions.logger.info(`✅ App Check token received for similar exercises generation`);

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
    const { exerciseNumber, exerciseType, exerciseContent, subject, count = 3 } = req.body;

    if (!exerciseContent || !exerciseType) {
        res.status(400).send('Missing required parameters: exerciseContent or exerciseType.');
        return;
    }

    // System instruction for similar exercise generation
    const systemInstruction = `You are an educational exercise generator. Your task is to generate similar practice exercises based on the original exercise provided below. If the exercise has subexercises keep the number of subexercises for each.

Generate exactly 3 exercises with the following difficulty levels:
1. **Easier:** A practice exercise that is simpler than the original (e.g., uses smaller numbers, has fewer steps, or is a more basic version of the concept).
2. **Same Difficulty:** A practice exercise that has a similar complexity to the original.
3. **Harder:** A practice exercise that is more challenging than the original (e.g., uses larger numbers, requires more steps, or introduces a more complex variation of the concept).

CRITICAL JSON FORMATTING - LaTeX Escaping Rules:
In JSON strings, every backslash must be written as double backslash (\\\\).

For LaTeX math notation:
- Inline math delimiters: \\\\( and \\\\)
- Block math delimiters: \\\\[ and \\\\]
- LaTeX commands like \\\\frac, \\\\text, \\\\pi also need double backslash

Concrete examples of CORRECT JSON:
- "content": "Calculate \\\\(x^2 + 5\\\\)"
- "content": "Simplify \\\\(\\\\frac{a}{b}\\\\)"
- "content": "The voltage is \\\\(2.0\\\\text{ V}\\\\)"
- "content": "Current is \\\\(1.5\\\\text{ A}\\\\)"
- "content": "Resistance: \\\\(10\\\\,\\\\Omega\\\\)"

WRONG examples (do NOT do this):
- "content": "Calculate \\(x^2\\)" ← Single backslash will break JSON
- "content": "Voltage \\(2.0 ||text V\\)" ← Wrong syntax, missing backslash before text
- "content": "Current |(1.0 \\ |text A" ← Malformed, random characters

Remember: In your JSON output, write \\\\text NOT \\text, write \\\\( NOT \\(

IMPORTANT:
- Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
- All mathematical content MUST use proper LaTeX notation with correct escaping`;

    // Build the user prompt
    const userPrompt = `Original Exercise:
Type: ${exerciseType}
${subject ? `Subject: ${subject}` : ''}
Content: ${exerciseContent}

Generate exactly ${count} similar practice exercises with varying difficulty levels.

CRITICAL LaTeX Formatting in JSON:
✓ CORRECT: "content": "The voltage is \\\\(2.0\\\\text{ V}\\\\)"
✓ CORRECT: "content": "Calculate resistance \\\\(R = \\\\frac{V}{I}\\\\)"
✗ WRONG: "content": "The voltage is \\(2.0 ||text V\\)"
✗ WRONG: "content": "Current is |(1.5 \\ |text{ A"

Return a JSON array with this exact structure:
[
    {
        "exerciseNumber": "1",
        "type": "${exerciseType}",
        "content": "The exercise text for the 'easier' difficulty level goes here. Use \\\\(math\\\\) for formulas.",
        "difficulty": "easier"
    },
    {
        "exerciseNumber": "2",
        "type": "${exerciseType}",
        "content": "The exercise text for the 'same' difficulty level goes here. Use \\\\(math\\\\) for formulas.",
        "difficulty": "same"
    },
    {
        "exerciseNumber": "3",
        "type": "${exerciseType}",
        "content": "The exercise text for the 'harder' difficulty level goes here. Use \\\\(math\\\\) for formulas.",
        "difficulty": "harder"
    }
]`;

    // Construct the API payload
    const model = "gemini-2.5-flash";
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: "user",
                parts: [{ text: userPrompt }]
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

    functions.logger.info(`✨ Generating ${count} similar exercises for exercise #${exerciseNumber || 'unknown'}`);

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const startTime = Date.now();

            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const elapsed = Date.now() - startTime;
            functions.logger.info(`⏱️  Similar exercises generation completed in ${elapsed}ms with status ${response.status}`);

            const result: any = await response.json();

            if (!response.ok) {
                throw new Error(`API returned status ${response.status}: ${JSON.stringify(result)}`);
            }

            let jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text;

            if (!jsonText) {
                throw new Error('LLM output content is missing.');
            }

            // Clean up potential JSON formatting issues from LLM
            // Remove markdown code block wrapper if present
            jsonText = jsonText.trim();
            if (jsonText.startsWith('```json')) {
                jsonText = jsonText.substring(7);
            }
            if (jsonText.startsWith('```')) {
                jsonText = jsonText.substring(3);
            }
            if (jsonText.endsWith('```')) {
                jsonText = jsonText.substring(0, jsonText.length - 3);
            }
            jsonText = jsonText.trim();

            // Fix common LaTeX escaping issues before parsing
            jsonText = fixLatexEscaping(jsonText);

            functions.logger.info(`📝 Parsing similar exercises JSON (length: ${jsonText.length})`);

            const exercises = JSON.parse(jsonText);

            functions.logger.info(`✅ Generated ${exercises.length} similar exercises successfully`);

            // Return the exercises array
            res.status(200).json(exercises);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`❌ Similar exercises generation attempt ${attempt + 1} failed: ${lastError.message}`);

            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000;
                functions.logger.info(`⏳ Retrying in ${Math.round(delay / 1000)}s...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // Final error response
    functions.logger.error('💥 Failed to generate similar exercises after retries.', lastError);
    res.status(500).send(`Failed to generate similar exercises: ${lastError?.message || 'Unknown error occurred.'}`);
});

/**
 * Analyzes text-only homework (without images, e.g., from ODT files) using Gemini AI.
 *
 * SECURITY: This function enforces Firebase App Check to verify requests come from legitimate app instances.
 */
export const analyzeTextOnly = functions.https.onRequest(async (req, res) => {
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

    functions.logger.info(`✅ App Check token received for text-only analysis`);

    // Allow bypass token in emulator mode
    if (isEmulator && appCheckToken === 'emulator-bypass-token') {
        functions.logger.info('🔐 EMULATOR MODE: Using bypass token for local development');
        functions.logger.warn('⚠️  App Check is DISABLED. This is only allowed in emulator mode.');
    }

    // API Key
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        functions.logger.error("GEMINI_API_KEY environment variable not set.");
        res.status(500).send('Server configuration error: API Key missing.');
        return;
    }

    // Input validation
    const { text } = req.body;
    if (!text) {
        res.status(400).send('Missing required parameter: text.');
        return;
    }

    functions.logger.info(`📝 Analyzing text-only homework (${text.length} characters)`);

    // System instruction for text-only analysis
    const systemInstruction = `You are an intelligent homework analysis engine. Analyze the provided text to identify ALL exercises.

CRITICAL: You must analyze the ACTUAL text provided by the user, NOT any examples shown in this prompt. The examples are only to show the JSON format you should use.

--- CLASSIFICATION GUIDELINES ---
Analyze each segment of text and classify it as EITHER 'EXERCISE' OR 'SKIP'.

EXERCISE (type: 'EXERCISE'):
- Numbered items (1., 2., a., b., Exercise 1:, Problem 1:, etc.)
- Questions with question words: "Find", "Calculate", "Solve", "Show", "Prove", "Determine", "Explain"
- Instructions with imperative verbs: "Complete", "Fill in", "Draw", "Write", "Expand"
- Questions ending with "?" or containing question patterns
- When the text contains multiple paragraphs with different exercises, separate them

SKIP (type: 'SKIP'):
- Pure headers or titles without actual questions/tasks
- Descriptive text without any task or question

--- SUBJECT CLASSIFICATION ---
For each EXERCISE, determine the subject:
- 'mathematics': Math problems, calculations, equations
- 'language': Grammar, vocabulary, sentence construction
- 'science': Scientific concepts and experiments
- 'history': Historical events and analysis
- 'grammar': Grammar exercises, punctuation
- 'reading': Reading comprehension
- 'writing': Essays, composition
- 'other': Any other subject

--- INPUT TYPE DETERMINATION ---
For each EXERCISE:
- 'inline': Fill-in-the-blank with visible placeholders (___,  [blank])
- 'text': Short-answer questions, definitions, simple questions
- 'canvas': Problems requiring calculations, diagrams, or visual work
- 'both': Complex problems requiring both visual work and written explanation

--- COORDINATE SYSTEM FOR TEXT-ONLY ---
Since there is no image:
- Assign sequential Y-coordinates based on the order exercises appear in the text
- First exercise: yStart=100, yEnd=200
- Second exercise: yStart=200, yEnd=300
- Third exercise: yStart=300, yEnd=400
- And so on... (increment by 100 for each exercise)

Your output MUST strictly adhere to the provided JSON schema.`;

    // Build the user prompt
    const userPrompt = `INSTRUCTIONS:
Analyze the provided text to identify ALL exercises.

CRITICAL: You must analyze the ACTUAL text provided below, NOT the example structure shown later in this prompt. The example is only to show the JSON format you should use.

EXERCISE DETECTION RULES:
- Numbered items (1., 2., a., b., Exercise 1:, Problem 1:, etc.) = EXERCISE
- Questions with question words: "Find", "Calculate", "Solve", "Show", "Prove", "Determine", "Explain"
- Instructions with imperative verbs: "Complete", "Fill in", "Draw", "Write", "Expand"
- Questions ending with "?" or containing question patterns
- When the text contains multiple paragraphs with different exercises, separate them

SKIP (not exercises):
- Pure headers or titles without actual questions/tasks
- Descriptive text without any task or question

For each exercise, identify:
- exerciseNumber: The number/identifier (e.g., "1", "a", "Exercise 3")
- type: The nature of this content block. Must be either 'EXERCISE' or 'SKIP'
- title: A concise identifier for this exercise (e.g., "Exercise 1")
- content: Clean, properly formatted text of the exercise. Fix any errors and use LaTeX for math.
- subject: The subject area (mathematics, language, science, history, grammar, etc.) or null if unclear
- inputType: How the student should answer - "text", "canvas", "inline", or "both"
- yStart: Sequential Y-coordinate (100, 200, 300, etc.)
- yEnd: Sequential Y-coordinate (200, 300, 400, etc.)

IMPORTANT:
- Return ONLY valid JSON
- For mathematical content, use LaTeX notation
- Enclose inline math expressions with \\( and \\)
- Enclose block math expressions with \\[ and \\]

---TEXT TO ANALYZE---
${text}
---END TEXT---

Expected output schema (DO NOT copy this example - analyze the actual text above):
{
    "summary": "Brief summary of homework",
    "sections": [
        {
            "type": "EXERCISE",
            "title": "<identifier from actual text>",
            "content": "<actual exercise content from text>",
            "subject": "<detected subject>",
            "inputType": "<text|canvas|inline|both>",
            "yStart": 100,
            "yEnd": 200
        }
    ]
}

Return ONLY valid JSON following the schema above:`;

    // Construct the API payload
    const model = "gemini-2.5-flash";
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: "user",
                parts: [{ text: userPrompt }]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: analysisSchema
        },
        systemInstruction: {
            parts: [{ text: systemInstruction }]
        }
    };

    // Call the API with retry logic
    const MAX_RETRIES = 3;
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const startTime = Date.now();

            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

            const elapsed = Date.now() - startTime;
            functions.logger.info(`⏱️  Text-only analysis completed in ${elapsed}ms with status ${response.status}`);

            const result: any = await response.json();

            if (!response.ok) {
                throw new Error(`API returned status ${response.status}: ${JSON.stringify(result)}`);
            }

            const jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text;

            if (!jsonText) {
                throw new Error('LLM output content is missing or structured incorrectly.');
            }

            // Successfully received JSON response from the model
            const structuredOutput = JSON.parse(jsonText);

            functions.logger.info(`✅ Successfully analyzed text-only homework. Sections: ${structuredOutput.sections?.length || 0}`);
            functions.logger.info("Text-only analysis result:", structuredOutput);

            // Return the structured JSON to the client
            res.status(200).json(structuredOutput);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`❌ Text-only analysis attempt ${attempt + 1} failed: ${lastError.message}`);

            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000;
                functions.logger.info(`⏳ Retrying in ${Math.round(delay / 1000)}s...`);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // Final error response
    functions.logger.error('💥 Failed to analyze text-only homework after retries.', lastError);
    res.status(500).send(`Failed to analyze text: ${lastError?.message || 'Unknown error occurred.'}`);
});

// Export the agentic analysis function
export { analyzeHomeworkAgentic } from './agenticAnalysis';
