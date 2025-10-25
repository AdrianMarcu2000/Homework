/**
 * Language Exercise Agent
 *
 * Specialized agent for analyzing language/grammar homework exercises
 * Handles: Grammar, vocabulary, reading comprehension, writing exercises
 */

import * as functions from 'firebase-functions';
import fetch from 'node-fetch';

// ============================================================================
// PROMPT
// ============================================================================

const LANGUAGE_EXERCISE_PROMPT = `You are a specialized language and grammar exercise analysis agent. Your expertise is in identifying, extracting, and analyzing language learning exercises from homework.

Analyze the provided language homework and extract ALL individual exercises with detailed information.

For each exercise you must determine:

1. QUESTION ANALYSIS:
   - Extract the complete question text
   - Identify the specific topic (e.g., "Verb Conjugation", "Vocabulary", "Reading Comprehension", "Grammar Rules")
   - Determine the language being studied (English, Spanish, French, German, etc.)
   - Assess difficulty: easy, medium, or hard
   - Estimate time to complete in minutes

2. INPUT TYPE DETERMINATION (CRITICAL):
   Decide which UI component the student should use to answer:

   - "inline": For fill-in-the-blank exercises within sentences
     Indicators: Blanks in sentences like "The cat ___ on the mat", "Je ___ français"
     Extract placeholder positions for inline answers

   - "text_input": For single word or short phrase answers
     Indicators: "What is the past tense of...", "Translate:", simple vocabulary questions

   - "text_area": For essay-style answers, paragraph writing, longer responses
     Indicators: "Write a paragraph about...", "Explain in your own words...", "Compose a story..."

   - "multiple_choice": For multiple choice questions
     Indicators: Options listed as A) B) C) D) or numbered choices

3. INPUT CONFIGURATION:
   - For "inline": Extract exact placeholder positions and what should fill them (word count, part of speech)
   - For "multiple_choice": Extract all option texts
   - For "text_area": Suggest min/max word counts based on question requirements
   - For "text_input": Specify expected answer length

4. EXERCISE POSITION:
   - Use the OCR block Y-coordinates to determine startY and endY (0.0 to 1.0)
   - This allows the app to crop the image to show just this exercise

5. LEARNING SUPPORT:
   - List related grammar/language concepts
   - Provide 3-5 step-by-step hints without giving the answer
   - For grammar exercises, reference relevant rules

Return ONLY valid JSON with NO markdown formatting:
{
  "type": "exercises",
  "subject": "language",
  "language": "English|Spanish|French|German|Other",
  "exercises": [
    {
      "exerciseNumber": 1,
      "questionText": "Complete problem text",
      "topic": "Specific language topic",
      "difficulty": "easy|medium|hard",
      "estimatedTimeMinutes": 5,
      "inputType": "text_area|text_input|inline|multiple_choice",
      "inputConfig": {
        "placeholders": ["blank1", "blank2"],
        "placeholderPositions": [{"start": 10, "end": 13, "index": 0}],
        "options": ["A) Option text", "B) Option text"],
        "minWords": 50,
        "maxWords": 200,
        "expectedLength": "short|medium|long"
      },
      "position": {
        "startY": 0.1,
        "endY": 0.25
      },
      "relatedConcepts": ["concept1", "concept2"],
      "solutionSteps": [
        "Step 1 hint",
        "Step 2 hint",
        "Step 3 hint"
      ]
    }
  ],
  "overallMetadata": {
    "totalExercises": 10,
    "topics": ["topic1", "topic2"],
    "estimatedTotalTime": 30,
    "difficultyDistribution": {
      "easy": 4,
      "medium": 5,
      "hard": 1
    }
  }
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
        // If parsing fails, log the problematic JSON for debugging
        functions.logger.error('JSON parsing failed. Problematic JSON:', jsonText.substring(0, 1000));
        throw new Error(`JSON parse error: ${(parseError as Error).message}`);
    }
}

// ============================================================================
// AGENT IMPLEMENTATION
// ============================================================================

export async function languageExerciseAgent(
    imageBase64: string,
    ocrText: string,
    ocrBlocks: OCRBlock[],
    routing: any,
    apiKey: string
): Promise<any> {
    const startTime = Date.now();
    functions.logger.info('📚 LANGUAGE EXERCISE AGENT: Starting detailed analysis');
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
                    { text: LANGUAGE_EXERCISE_PROMPT },
                    base64ToGenerativePart(imageBase64, 'image/jpeg'),
                    { text: `\n\nOCR Text with Positions:\n${ocrContext}` },
                    { text: `\n\nGrade Level: ${routing.gradeLevel}` },
                    { text: `\n\nSubject: ${routing.subject}` }
                ]
            }
        ],
        generationConfig: {
            temperature: 0.3,
            maxOutputTokens: 8192,
        }
    };

    functions.logger.info('📤 Sending request to Gemini API (Language Exercise Agent)...');
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    const elapsed = Date.now() - startTime;
    functions.logger.info(`📥 Language Exercise Agent response received in ${elapsed}ms with status ${response.status}`);

    const result: any = await response.json();

    if (!response.ok) {
        functions.logger.error('❌ Language Exercise Agent API error', { status: response.status, result });
        throw new Error(`Language Agent API error: ${response.status} - ${JSON.stringify(result)}`);
    }

    const responseText = result.candidates?.[0]?.content?.parts?.[0]?.text;
    functions.logger.info('📝 Language Exercise Agent raw response (first 500 chars):');
    functions.logger.info(responseText?.substring(0, 500) + '...');

    const analysis = extractJSON(responseText);

    // Detailed logging of analysis results
    const exerciseCount = analysis.exercises?.length || 0;
    const metadata = analysis.overallMetadata;

    functions.logger.info('✅ LANGUAGE EXERCISE AGENT: Analysis complete', {
        exerciseCount: exerciseCount,
        language: analysis.language,
        totalExercises: metadata?.totalExercises,
        topics: metadata?.topics,
        estimatedTotalTime: metadata?.estimatedTotalTime + ' min',
        difficultyDistribution: metadata?.difficultyDistribution,
        elapsedMs: elapsed
    });

    // Log individual exercises
    if (analysis.exercises && analysis.exercises.length > 0) {
        functions.logger.info('📚 Extracted Exercises:');
        analysis.exercises.forEach((ex: any, idx: number) => {
            functions.logger.info(`  Exercise ${idx + 1}: ${ex.topic} (${ex.difficulty}) - Input Type: ${ex.inputType}`);
        });
    }

    return analysis;
}
