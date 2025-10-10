import * as functions from 'firebase-functions';
import fetch from 'node-fetch';


// The Analysis Schema provided by the user. This defines the required output structure.
// This is converted from the user's TypeScript object into a standard JavaScript object
// that defines the JSON structure expected from the LLM.
const analysisSchema = {
    type: "OBJECT",
    properties: {
        summary: {
            type: "STRING",
            description: "A concise, high-level summary of the entire document (the image and its text content)."
        },
        sections: {
            type: "ARRAY",
            description: "A chronological list of content blocks (exercises or lessons) derived from the image, segmented by visual and coordinate data (yStart to yEnd).",
            items: {
                type: "OBJECT",
                properties: {
                    type: {
                        type: "STRING",
                        description: "The nature of this content block. Must be either 'EXERCISE' (a problem to be solved) or 'LESSON' (an informational or teaching block, definition, or example).",
                        enum: ["EXERCISE", "LESSON"]
                    },
                    title: {
                        type: "STRING",
                        description: "A concise title or identifier for this specific block (e.g., 'Exercise 1', 'Geometric Principles')."
                    },
                    content: {
                        type: "STRING",
                        description: "The detailed, synthesized content and text of the entire section."
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
 */
export const analyzeHomework = functions.https.onRequest(async (req, res) => {
    // Check for POST request
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed. Use POST.');
        return;
    }

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

    // 1. Define the system instruction for the LLM's role, including detailed classification logic
    const systemInstruction = `You are an intelligent document analysis and segmentation engine. Your task is to analyze the provided homework image and its OCR text (which includes Y-coordinates for each paragraph).

Your primary goal is to segment the content into distinct, visually-grounded sections, outputting the result in the required JSON schema. IGNORE content that is purely a title, header, footer, or page number ('NEITHER' category).

--- CLASSIFICATION GUIDELINES ---
Analyze each segment of text and classify it as EITHER 'EXERCISE' OR 'LESSON'.

EXERCISE (Tasks for students, type: 'EXERCISE'):
- Content that contains questions, problems, or tasks that ASK the student to do something.
- If the text contains ANY questions, question marks, or asks the student to perform a task, it is almost ALWAYS an exercise, NOT a lesson.
- Contains question words: "Find", "Calculate", "Solve", "Show", "Prove", "Determine".
- Contains instruction words: "Complete", "Fill in", "Draw", "Explain".
- Problems WITHOUT complete solutions shown.

LESSON (Theoretical content, type: 'LESSON'):
- Explanations, definitions, formulas, theorems, or core concepts.
- Solved examples WITH complete solutions already shown.
- Educational text that TEACHES (does NOT ask questions or request action).
- Must be purely informational/instructional.
- NO question marks or imperative verbs (unless part of a quote/formula).
--- END GUIDELINES ---

--- COORDINATE & SYNTHESIS INSTRUCTIONS ---
1. Use the 'ocrJsonText' data, paying close attention to the Y-coordinates to define the visual boundaries of each section.
2. The 'yStart' must be the MINIMUM Y-coordinate of any text paragraph belonging to that section.
3. The 'yEnd' must be the MAXIMUM Y-coordinate of any text paragraph belonging to that section.
4. Synthesize the 'content' field for each section, making it readable and coherent, using the OCR data as your source of truth.
5. Your output MUST strictly adhere to the provided JSON schema.`;


    // 2. Define the user prompt, combining the image and text data
    const userPrompt = `Analyze the document based on the following OCR text, which includes Y-coordinates for segmentation:
--- OCR TEXT DATA ---
${ocrJsonText}
--- END OCR TEXT DATA ---

Based on the visual cues from the image and the segmentation information in the OCR data, produce the structured JSON analysis following the provided schema and classification rules.`;

    // 3. Construct the API payload
    const model = "gemini-2.5-flash-preview-05-20";
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

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const response = await fetch(apiUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });

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
            
            // Return the structured JSON to the client
            res.status(200).json(structuredOutput);
            return;

        } catch (error) {
            lastError = error as Error;
            functions.logger.warn(`Attempt ${attempt + 1} failed: ${lastError.message}`);
            if (attempt < MAX_RETRIES - 1) {
                const delay = Math.pow(2, attempt) * 1000 + Math.random() * 1000; // Exponential backoff + jitter
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    // 5. Final error response after all retries fail
    functions.logger.error('Failed to get LLM response after multiple retries.', lastError);
    res.status(500).send(`Failed to analyze document: ${lastError?.message || 'Unknown error occurred.'}`);
});