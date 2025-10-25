/**
 * Science Exercise Agent
 *
 * Specialized agent for analyzing science homework exercises
 * Handles: Physics, Chemistry, Biology - calculations, diagrams, experiments
 */

import * as functions from 'firebase-functions';
import fetch from 'node-fetch';

// ============================================================================
// PROMPT
// ============================================================================

const SCIENCE_EXERCISE_PROMPT = `You are a specialized science exercise analysis agent. Your expertise is in identifying, extracting, and analyzing science exercises from homework covering Physics, Chemistry, and Biology.

Analyze the provided science homework and extract ALL individual exercises with detailed information.

For each exercise you must determine:

1. QUESTION ANALYSIS:
   - Extract the complete question text
   - Convert all scientific notation, formulas, and equations to LaTeX format
   - Identify the specific topic (e.g., "Newton's Laws", "Chemical Equations", "Cell Biology", "Circuits")
   - Identify the science branch (Physics, Chemistry, Biology)
   - Assess difficulty: easy, medium, or hard
   - Estimate time to complete in minutes

2. INPUT TYPE DETERMINATION (CRITICAL):
   Decide which UI component the student should use to answer:

   - "math_canvas": For problems requiring calculations, equations, scientific formulas
     Indicators: "Calculate", "Find the value", numerical problems with units, formula-based questions
     Physics: Force calculations, velocity, acceleration, energy
     Chemistry: Stoichiometry, molarity, balancing equations
     Biology: Punnett squares, population calculations

   - "drawing_canvas": For diagrams, sketches, scientific illustrations
     Indicators: "Draw", "Sketch", "Label the diagram", "Illustrate"
     Physics: Circuit diagrams, free body diagrams, ray diagrams
     Chemistry: Molecular structures, apparatus setup
     Biology: Cell diagrams, anatomical sketches, ecosystem diagrams

   - "text_area": For explanations, experiment descriptions, essay-style science answers
     Indicators: "Explain why", "Describe the process", "What happens when", "Compare and contrast"

   - "text_input": For single word/phrase answers, simple definitions
     Indicators: "What is the name of", "Define", simple factual recall

   - "inline": For fill-in-the-blank within equations or scientific text
     Indicators: Blanks in formulas like "F = m × ___", "The organelle responsible for ___ is ___"

   - "multiple_choice": For multiple choice questions
     Indicators: Options listed as A) B) C) D) or numbered choices

3. INPUT CONFIGURATION:
   - For "inline": Extract exact placeholder positions
   - For "multiple_choice": Extract all option texts
   - For "math_canvas": Note if units are required, grid needed
   - For "drawing_canvas": Specify what type of diagram (circuit, molecule, cell, etc.)
   - For "text_area": Suggest min/max word counts if applicable

4. EXERCISE POSITION:
   - Use the OCR block Y-coordinates to determine startY and endY (0.0 to 1.0)
   - This allows the app to crop the image to show just this exercise

5. LEARNING SUPPORT:
   - List related scientific concepts
   - Provide 3-5 step-by-step hints without giving the answer
   - For calculations, hint at formulas or approaches
   - For diagrams, hint at key components to include

Return ONLY valid JSON with NO markdown formatting:
{
  "type": "exercises",
  "subject": "science",
  "scienceBranch": "Physics|Chemistry|Biology|General",
  "exercises": [
    {
      "exerciseNumber": 1,
      "questionText": "Complete problem text",
      "questionLatex": "LaTeX formatted version (if applicable)",
      "topic": "Specific science topic",
      "scienceBranch": "Physics|Chemistry|Biology",
      "difficulty": "easy|medium|hard",
      "estimatedTimeMinutes": 5,
      "inputType": "math_canvas|drawing_canvas|text_area|text_input|inline|multiple_choice",
      "inputConfig": {
        "placeholders": ["value1", "value2"],
        "placeholderPositions": [{"start": 10, "end": 13, "index": 0}],
        "options": ["A) Option text", "B) Option text"],
        "canvasType": "calculation|diagram",
        "diagramType": "circuit|molecule|cell|apparatus|other",
        "requiresGrid": true,
        "requiresUnits": true,
        "expectedUnits": "m/s|kg|mol|V|etc",
        "minWords": 50,
        "maxWords": 200
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
    "scienceBranches": ["Physics", "Chemistry"],
    "topics": ["topic1", "topic2"],
    "estimatedTotalTime": 45,
    "difficultyDistribution": {
      "easy": 3,
      "medium": 5,
      "hard": 2
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

export async function scienceExerciseAgent(
    imageBase64: string,
    ocrText: string,
    ocrBlocks: OCRBlock[],
    routing: any,
    apiKey: string
): Promise<any> {
    const startTime = Date.now();
    functions.logger.info('🔬 SCIENCE EXERCISE AGENT: Starting detailed analysis');
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
                    { text: SCIENCE_EXERCISE_PROMPT },
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

    functions.logger.info('📤 Sending request to Gemini API (Science Exercise Agent)...');
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    const elapsed = Date.now() - startTime;
    functions.logger.info(`📥 Science Exercise Agent response received in ${elapsed}ms with status ${response.status}`);

    const result: any = await response.json();

    if (!response.ok) {
        functions.logger.error('❌ Science Exercise Agent API error', { status: response.status, result });
        throw new Error(`Science Agent API error: ${response.status} - ${JSON.stringify(result)}`);
    }

    const responseText = result.candidates?.[0]?.content?.parts?.[0]?.text;
    functions.logger.info('📝 Science Exercise Agent raw response (first 500 chars):');
    functions.logger.info(responseText?.substring(0, 500) + '...');

    const analysis = extractJSON(responseText);

    // Detailed logging of analysis results
    const exerciseCount = analysis.exercises?.length || 0;
    const metadata = analysis.overallMetadata;

    functions.logger.info('✅ SCIENCE EXERCISE AGENT: Analysis complete', {
        exerciseCount: exerciseCount,
        scienceBranch: analysis.scienceBranch,
        totalExercises: metadata?.totalExercises,
        scienceBranches: metadata?.scienceBranches,
        topics: metadata?.topics,
        estimatedTotalTime: metadata?.estimatedTotalTime + ' min',
        difficultyDistribution: metadata?.difficultyDistribution,
        elapsedMs: elapsed
    });

    // Log individual exercises
    if (analysis.exercises && analysis.exercises.length > 0) {
        functions.logger.info('🔬 Extracted Exercises:');
        analysis.exercises.forEach((ex: any, idx: number) => {
            const branch = ex.scienceBranch || 'General';
            functions.logger.info(`  Exercise ${idx + 1}: [${branch}] ${ex.topic} (${ex.difficulty}) - Input Type: ${ex.inputType}`);
        });
    }

    return analysis;
}
