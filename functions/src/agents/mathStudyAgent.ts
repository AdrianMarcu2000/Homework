/**
 * Math Study Agent
 *
 * Specialized agent for analyzing math study material (lessons, theory, examples)
 * Different from exercise agent - focuses on learning content rather than problems to solve
 */

import * as functions from 'firebase-functions';
import fetch from 'node-fetch';

// ============================================================================
// PROMPT
// ============================================================================

const MATH_STUDY_PROMPT = `You are a specialized mathematics study material analysis agent. Your expertise is in identifying and analyzing mathematical lessons, theory, and study content (NOT exercises to be solved).

Analyze the provided mathematics study material and extract the learning content.

Your task is to:

1. IDENTIFY STUDY MATERIAL:
   - Lesson explanations and theory
   - Worked examples (problems already solved with steps shown)
   - Definitions and theorems
   - Formulas and rules
   - Diagrams and visual explanations

2. CREATE SUMMARY:
   - Title of the lesson/topic
   - Main topics covered
   - Key points (mark importance: high/medium/low)
   - List of important formulas with LaTeX formatting

3. EXTRACT WORKED EXAMPLES:
   - If the material contains worked examples (problems with solutions shown), extract them
   - Include the problem statement
   - Include the solution steps shown
   - Note the topic/concept demonstrated

4. GENERATE PRACTICE EXERCISES:
   - Based on the study material, create 3-5 NEW practice exercises
   - These should be similar to worked examples but with different values
   - Vary difficulty: easier, same level, harder
   - For each practice exercise, determine appropriate input type

5. POSITION TRACKING:
   - Use OCR block Y-coordinates to identify sections of the study material
   - This allows the app to show relevant parts of the image

Return ONLY valid JSON with NO markdown formatting:
{
  "type": "study_material",
  "subject": "math",
  "summary": {
    "title": "Main topic/lesson title",
    "mainTopics": ["topic1", "topic2"],
    "keyPoints": [
      {
        "point": "Important concept or rule",
        "importance": "high|medium|low"
      }
    ],
    "formulas": [
      {
        "name": "Formula name",
        "latex": "\\\\(formula in LaTeX\\\\)",
        "description": "When to use this formula"
      }
    ],
    "position": {
      "startY": 0.0,
      "endY": 1.0
    }
  },
  "workedExamples": [
    {
      "exampleNumber": 1,
      "problemStatement": "The example problem",
      "problemLatex": "\\\\(problem in LaTeX\\\\)",
      "topic": "Topic demonstrated",
      "solutionSteps": [
        "Step 1 as shown in material",
        "Step 2 as shown in material"
      ],
      "position": {
        "startY": 0.2,
        "endY": 0.4
      }
    }
  ],
  "practiceExercises": [
    {
      "exerciseNumber": 1,
      "questionText": "New practice problem based on study material",
      "questionLatex": "LaTeX formatted version",
      "topic": "Topic from study material",
      "difficulty": "easy|medium|hard",
      "estimatedTimeMinutes": 5,
      "inputType": "math_canvas|text_area|text_input|inline|multiple_choice",
      "inputConfig": {
        "canvasType": "math|freeform",
        "requiresGrid": false
      },
      "relatedConcepts": ["concept1", "concept2"],
      "hints": [
        "Hint 1",
        "Hint 2"
      ]
    }
  ],
  "metadata": {
    "gradeLevel": "Elementary|MiddleSchool|HighSchool|University",
    "topics": ["topic1", "topic2"],
    "totalWorkedExamples": 3,
    "totalPracticeExercises": 5,
    "estimatedStudyTime": 30
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

export async function mathStudyAgent(
    imageBase64: string,
    ocrText: string,
    ocrBlocks: OCRBlock[],
    routing: any,
    apiKey: string
): Promise<any> {
    const startTime = Date.now();
    functions.logger.info('📖 MATH STUDY AGENT: Starting study material analysis');
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
                    { text: MATH_STUDY_PROMPT },
                    base64ToGenerativePart(imageBase64, 'image/jpeg'),
                    { text: `\n\nOCR Text with Positions:\n${ocrContext}` },
                    { text: `\n\nGrade Level: ${routing.gradeLevel}` }
                ]
            }
        ],
        generationConfig: {
            temperature: 0.3,
            maxOutputTokens: 8192,
        }
    };

    functions.logger.info('📤 Sending request to Gemini API (Math Study Agent)...');
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    const elapsed = Date.now() - startTime;
    functions.logger.info(`📥 Math Study Agent response received in ${elapsed}ms with status ${response.status}`);

    const result: any = await response.json();

    if (!response.ok) {
        functions.logger.error('❌ Math Study Agent API error', { status: response.status, result });
        throw new Error(`Math Study Agent API error: ${response.status} - ${JSON.stringify(result)}`);
    }

    const responseText = result.candidates?.[0]?.content?.parts?.[0]?.text;
    functions.logger.info('📝 Math Study Agent raw response (first 500 chars):');
    functions.logger.info(responseText?.substring(0, 500) + '...');

    const analysis = extractJSON(responseText);

    // Detailed logging of analysis results
    const metadata = analysis.metadata;
    const summary = analysis.summary;

    functions.logger.info('✅ MATH STUDY AGENT: Analysis complete', {
        lessonTitle: summary?.title,
        mainTopics: summary?.mainTopics,
        workedExamplesCount: analysis.workedExamples?.length || 0,
        practiceExercisesCount: analysis.practiceExercises?.length || 0,
        totalFormulas: summary?.formulas?.length || 0,
        estimatedStudyTime: metadata?.estimatedStudyTime + ' min',
        elapsedMs: elapsed
    });

    // Log worked examples
    if (analysis.workedExamples && analysis.workedExamples.length > 0) {
        functions.logger.info('📚 Worked Examples Found:');
        analysis.workedExamples.forEach((ex: any, idx: number) => {
            functions.logger.info(`  Example ${idx + 1}: ${ex.topic} (${ex.solutionSteps?.length || 0} steps shown)`);
        });
    }

    // Log generated practice exercises
    if (analysis.practiceExercises && analysis.practiceExercises.length > 0) {
        functions.logger.info('✏️  Practice Exercises Generated:');
        analysis.practiceExercises.forEach((ex: any, idx: number) => {
            functions.logger.info(`  Practice ${idx + 1}: ${ex.topic} (${ex.difficulty}) - Input Type: ${ex.inputType}`);
        });
    }

    return analysis;
}
