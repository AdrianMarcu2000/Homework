/**
 * Math Exercise Agent
 *
 * Specialized agent for analyzing mathematics exercise homework
 * Handles: Problem-solving exercises, calculations, equations, graphs
 */

import * as functions from 'firebase-functions';
import fetch from 'node-fetch';

// ============================================================================
// PROMPT
// ============================================================================

const MATH_EXERCISE_PROMPT = `You are a specialized mathematics exercise extraction agent. Your ONLY job is to identify and extract individual exercises from homework - NOT to solve them or provide hints.

Extract ALL individual exercises from the provided mathematics homework.

CRITICAL - Exercise Grouping:
- If an exercise has subparts (2a, 2b, 2c), treat them as ONE SINGLE exercise
- Combine all subparts into a single questionText and questionLatex
- Use the parent exercise number (e.g., "2" not "2a")
- Example: "Exercise 2" with parts a, b, c should be one exercise, not three

For each exercise:

1. IDENTIFICATION:
   - Extract the complete question text exactly as written (including ALL subparts)
   - Convert all mathematical notation to LaTeX format
   - Verify the task makes logical sense (e.g., "solve for x" has an equation, "calculate" has numbers)
   - Identify the specific topic (e.g., "Comparing Decimals", "Linear Equations", "Derivatives")

2. POSITION (CRITICAL - Y coordinate system where Y=0 is TOP):
   - Use OCR block Y-coordinates to determine startY and endY (0.0 to 1.0)
   - Y=0.0 is the TOP of the image
   - Y=1.0 is the BOTTOM of the image
   - For exercises with subparts, position must span from first subpart to last subpart
   - Ensure position captures the entire exercise including any diagrams

3. INPUT TYPE (how student will answer):
   - "text_input": Single answer (number, word, true/false)
   - "inline": Fill-in-blank within text/equations
   - "multiple_choice": A/B/C/D options provided
   - "text_area": Essay/explanation required
   - "math_canvas": Show work, calculations, equations
   - "drawing_canvas": Geometric diagrams, sketches

IMPORTANT:
- Do NOT generate solutions, hints, or answers
- Do NOT include relatedConcepts or solutionSteps
- Keep output MINIMAL and focused on extraction only

CRITICAL - LaTeX Escaping in JSON:
- Use single backslash for LaTeX commands in JSON strings
- Example: "$5 \times 10$" NOT "$5 \\times 10$"
- Example: "$\frac{1}{2}$" NOT "$\\frac{1}{2}$"
- Example: "$\sqrt{16}$" NOT "$\\sqrt{16}$"

Return ONLY valid JSON:
{
  "type": "exercises",
  "subject": "math",
  "exercises": [
    {
      "exerciseNumber": "2",
      "questionText": "Say whether the mathematical statements are true or false:\na) 0.599 > 6.0\nb) 5 × 1999 ≈ 10000\nc) 8.1 = 8 1/10",
      "questionLatex": "a) $0.599 > 6.0$\nb) $5 \\times 1999 \\approx 10000$\nc) $8.1 = 8\\frac{1}{10}$",
      "topic": "Comparing Numbers and Operations",
      "inputType": "text_input",
      "position": {
        "startY": 0.06,
        "endY": 0.82
      }
    }
  ]
}`;

// ============================================================================
// INTERFACES
// ============================================================================

interface OCRBlock {
    text: string;
    startY: number;
    endY: number;
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function formatOCRBlocksWithPositions(ocrBlocks: OCRBlock[]): string {
    if (!ocrBlocks || ocrBlocks.length === 0) {
        return 'No OCR data available';
    }

    return ocrBlocks
        .map((block, index) => {
            return `[Block ${index + 1}] Y: ${block.startY.toFixed(3)}-${block.endY.toFixed(3)} | Text: ${block.text}`;
        })
        .join('\n');
}

function base64ToGenerativePart(base64Image: string, mimeType: string) {
    return {
        inlineData: {
            data: base64Image,
            mimeType,
        },
    };
}

/**
 * Robust JSON extraction from AI responses
 * Handles: markdown code blocks, trailing commas, truncated JSON
 */
function extractJSON(responseText: string): any {
    if (!responseText) {
        throw new Error('Empty response text');
    }

    // Remove markdown code blocks if present
    let cleaned = responseText.replace(/```json\n?/g, '').replace(/```\n?/g, '');

    // Try to find JSON object
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/);

    if (!jsonMatch) {
        throw new Error('No JSON structure found in response');
    }

    let jsonText = jsonMatch[0];

    // Remove trailing commas before closing braces/brackets (common AI error)
    jsonText = jsonText.replace(/,(\s*[}\]])/g, '$1');

    try {
        return JSON.parse(jsonText);
    } catch (parseError) {
        // Try to fix truncated JSON by closing incomplete structures
        functions.logger.warn('Initial JSON parse failed, attempting to fix truncated response...');

        // Attempt to close incomplete strings, arrays, and objects
        let fixed = jsonText;

        // Count unclosed braces/brackets
        const openBraces = (fixed.match(/\{/g) || []).length;
        const closeBraces = (fixed.match(/\}/g) || []).length;
        const openBrackets = (fixed.match(/\[/g) || []).length;
        const closeBrackets = (fixed.match(/\]/g) || []).length;

        // If there's an incomplete string, close it
        const quotes = (fixed.match(/"/g) || []).length;
        if (quotes % 2 !== 0) {
            fixed += '"';
        }

        // Close unclosed arrays
        for (let i = 0; i < (openBrackets - closeBrackets); i++) {
            fixed += ']';
        }

        // Close unclosed objects
        for (let i = 0; i < (openBraces - closeBraces); i++) {
            fixed += '}';
        }

        try {
            functions.logger.info('Successfully fixed truncated JSON');
            return JSON.parse(fixed);
        } catch (retryError) {
            // Still failed, log and throw
            functions.logger.error('JSON parsing failed after repair attempt');
            functions.logger.error('Original JSON (first 1000 chars):', jsonText.substring(0, 1000));
            throw new Error(`JSON parse error: ${(parseError as Error).message}`);
        }
    }
}

// ============================================================================
// AGENT IMPLEMENTATION
// ============================================================================

export async function mathExerciseAgent(
    imageBase64: string,
    ocrText: string,
    ocrBlocks: OCRBlock[],
    routing: any,
    apiKey: string
): Promise<any> {
    const startTime = Date.now();
    functions.logger.info('🧮 MATH EXERCISE AGENT: Starting detailed analysis');
    functions.logger.info('📊 Input: ' + ocrBlocks.length + ' OCR blocks, Grade Level: ' + routing.gradeLevel);

    const model = 'gemini-2.5-flash';
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const ocrContext = formatOCRBlocksWithPositions(ocrBlocks);
    functions.logger.info('📝 OCR context prepared (' + ocrContext.length + ' chars)');

    const payload = {
        contents: [
            {
                role: 'user',
                parts: [
                    { text: MATH_EXERCISE_PROMPT },
                    base64ToGenerativePart(imageBase64, 'image/jpeg'),
                    { text: `\n\nOCR Text with Positions:\n${ocrContext}` },
                    { text: `\n\nGrade Level: ${routing.gradeLevel}` }
                ]
            }
        ],
        generationConfig: {
            temperature: 0.2,  // Lower temperature for precise extraction
            maxOutputTokens: 8192,  // Extraction-only but needs room for multiple exercises
        }
    };

    functions.logger.info('📤 Sending request to Gemini API (Math Exercise Agent)...');
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    const elapsed = Date.now() - startTime;
    functions.logger.info(`📥 Math Exercise Agent response received in ${elapsed}ms with status ${response.status}`);

    const result: any = await response.json();

    if (!response.ok) {
        functions.logger.error('❌ Math Exercise Agent API error', { status: response.status, result });
        throw new Error(`Math Agent API error: ${response.status} - ${JSON.stringify(result)}`);
    }

    // Check for safety blocks or empty responses
    if (!result.candidates || result.candidates.length === 0) {
        functions.logger.error('❌ No candidates in response', result);
        throw new Error('Gemini API returned no candidates. Possible safety block or invalid request.');
    }

    const candidate = result.candidates[0];

    // Check finish reason
    if (candidate.finishReason && candidate.finishReason !== 'STOP') {
        functions.logger.warn(`⚠️  Non-standard finish reason: ${candidate.finishReason}`);
        if (candidate.finishReason === 'SAFETY') {
            throw new Error('Response blocked by safety filters');
        }
        if (candidate.finishReason === 'MAX_TOKENS') {
            functions.logger.warn('⚠️  Response truncated due to max tokens - may cause JSON parsing errors');
        }
    }

    const responseText = candidate.content?.parts?.[0]?.text;

    if (!responseText) {
        functions.logger.error('❌ Empty response text from Gemini');
        functions.logger.error('Full candidate:', JSON.stringify(candidate, null, 2));
        throw new Error('Gemini API returned empty response text');
    }

    functions.logger.info('📝 Math Exercise Agent raw response:');
    functions.logger.info(responseText);

    const analysis = extractJSON(responseText);

    // Fix LaTeX escaping: Gemini over-escapes backslashes (\\times -> \times)
    // Also add default values for optional fields that Swift model expects
    if (analysis.exercises && Array.isArray(analysis.exercises)) {
        analysis.exercises.forEach((ex: any) => {
            if (ex.questionLatex && typeof ex.questionLatex === 'string') {
                // Replace double backslashes with single backslashes
                ex.questionLatex = ex.questionLatex.replace(/\\\\/g, '\\');
            }

            // Ensure exerciseNumber is a string (convert if needed)
            if (typeof ex.exerciseNumber !== 'string') {
                ex.exerciseNumber = String(ex.exerciseNumber);
            }

            // Add optional fields with defaults if missing (for Swift model compatibility)
            if (!ex.difficulty) ex.difficulty = null;
            if (!ex.estimatedTimeMinutes) ex.estimatedTimeMinutes = null;
            if (!ex.inputConfig) ex.inputConfig = null;
            if (!ex.relatedConcepts) ex.relatedConcepts = null;
            if (!ex.solutionSteps) ex.solutionSteps = null;
        });
    }

    // Detailed logging of analysis results
    const exerciseCount = analysis.exercises?.length || 0;

    functions.logger.info('✅ MATH EXERCISE AGENT: Extraction complete', {
        exerciseCount: exerciseCount,
        elapsedMs: elapsed
    });

    // Log individual exercises
    if (analysis.exercises && analysis.exercises.length > 0) {
        functions.logger.info('📚 Extracted Exercises:');
        analysis.exercises.forEach((ex: any, idx: number) => {
            functions.logger.info(`  [${ex.exerciseNumber}] ${ex.topic} - Input: ${ex.inputType} - Position: Y ${ex.position?.startY?.toFixed(2)}-${ex.position?.endY?.toFixed(2)}`);
        });
    }

    return analysis;
}
