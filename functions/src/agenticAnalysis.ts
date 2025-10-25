/**
 * Agentic Multi-Agent Homework Analysis
 *
 * This file implements the multi-agent homework analysis system with:
 * - Router Agent: Classifies homework by subject/type/grade
 * - Specialized Agents: Math, Science, Language experts per content type
 */

import * as functions from 'firebase-functions';
import fetch from 'node-fetch';
import { mathExerciseAgent } from './agents/mathExerciseAgent';
import { mathStudyAgent } from './agents/mathStudyAgent';
import { scienceExerciseAgent } from './agents/scienceExerciseAgent';
import { languageExerciseAgent } from './agents/languageExerciseAgent';

// ============================================================================
// PROMPTS
// ============================================================================

const ROUTER_PROMPT = `You are a homework classification expert. Your job is to analyze homework images and OCR text to classify the content accurately.

Analyze the provided homework and classify it along these dimensions:

1. SUBJECT: Identify the primary academic subject
   Options: Math, Science-Physics, Science-Chemistry, Science-Biology, Language-English, Language-Spanish, Language-French, Language-German, History, Geography, Art, Music, PE, CS, Other

2. CONTENT_TYPE: Determine what type of content this is
   - "study_material": Lesson explanations, theory, diagrams meant for students to study and learn from
   - "exercises": Problems, questions, or tasks for students to solve/answer
   - "hybrid": Contains both study material (explanations/theory) and exercises to solve

3. GRADE_LEVEL: Estimate the educational level
   Options: Elementary, MiddleSchool, HighSchool, University

4. RECOMMENDED_AGENT: Based on your classification, recommend which specialized agent should handle this
   Format: "{subject}_{type}_agent"
   Examples:
   - "math_exercise_agent" - for math homework with exercises to solve
   - "math_study_agent" - for math theory/lessons to study
   - "science_hybrid_agent" - for science content with both theory and exercises
   - "language_exercise_agent" - for language exercises

IMPORTANT: Return ONLY valid JSON in this exact format:
{
  "subject": "subject name",
  "contentType": "study_material|exercises|hybrid",
  "gradeLevel": "Elementary|MiddleSchool|HighSchool|University",
  "recommendedAgent": "agent_name",
  "confidence": 0.95
}`;

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

interface OCRBlock {
    text: string;
    startY: number;
    endY: number;
}

function ocrBlocksToText(ocrBlocks: OCRBlock[]): string {
    if (!ocrBlocks || ocrBlocks.length === 0) {
        return 'No OCR text available';
    }
    return ocrBlocks.map(block => block.text).join('\n');
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
// AGENT IMPLEMENTATIONS
// ============================================================================

async function routerAgent(imageBase64: string, ocrText: string, apiKey: string): Promise<any> {
    const startTime = Date.now();
    functions.logger.info('🤖 ROUTER AGENT: Starting classification');
    functions.logger.info('📊 Input: Image size = ' + Math.round(imageBase64.length / 1024) + 'KB, OCR text length = ' + ocrText.length + ' chars');

    const model = 'gemini-2.5-flash';
    const apiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const payload = {
        contents: [
            {
                role: 'user',
                parts: [
                    { text: ROUTER_PROMPT },
                    base64ToGenerativePart(imageBase64, 'image/jpeg'),
                    { text: `\n\nOCR Extracted Text:\n${ocrText}` }
                ]
            }
        ],
        generationConfig: {
            temperature: 0.2,
            maxOutputTokens: 1024,  // Simple classification, but model needs room to think
        }
    };

    functions.logger.info('📤 Sending request to Gemini API (Router Agent)...');
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    const elapsed = Date.now() - startTime;
    functions.logger.info(`📥 Router Agent response received in ${elapsed}ms with status ${response.status}`);

    const result: any = await response.json();

    if (!response.ok) {
        functions.logger.error('❌ Router Agent API error', { status: response.status, result });
        throw new Error(`Router API error: ${response.status} - ${JSON.stringify(result)}`);
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
            functions.logger.error('❌ Router Agent hit MAX_TOKENS. Full candidate:', JSON.stringify(candidate, null, 2));
            throw new Error('Router Agent exceeded token limit - prompt may be too complex');
        }
    }

    const responseText = candidate.content?.parts?.[0]?.text;

    if (!responseText) {
        functions.logger.error('❌ Empty response text from Gemini', { candidate });
        throw new Error('Gemini API returned empty response text');
    }

    functions.logger.info('📝 Router Agent raw response:');
    functions.logger.info(responseText);

    const routing = extractJSON(responseText);
    functions.logger.info('✅ ROUTER AGENT: Classification complete', {
        subject: routing.subject,
        contentType: routing.contentType,
        gradeLevel: routing.gradeLevel,
        agent: routing.recommendedAgent,
        confidence: routing.confidence,
        elapsedMs: elapsed
    });

    return routing;
}

// ============================================================================
// ROUTING LOGIC
// ============================================================================

async function routeToSpecializedAgent(
    routing: any,
    imageBase64: string,
    ocrText: string,
    ocrBlocks: OCRBlock[],
    apiKey: string
): Promise<any> {
    const agentName = routing.recommendedAgent;
    functions.logger.info('🔀 ROUTING: Selecting specialized agent');
    functions.logger.info('  → Recommended Agent: ' + agentName);
    functions.logger.info('  → Subject: ' + routing.subject);
    functions.logger.info('  → Content Type: ' + routing.contentType);

    // Route to appropriate agent based on recommendation
    switch (agentName) {
        case 'math_exercise_agent':
            functions.logger.info('✅ Routing to Math Exercise Agent');
            return mathExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);

        case 'math_study_agent':
            functions.logger.info('✅ Routing to Math Study Agent');
            return mathStudyAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);

        case 'science_exercise_agent':
        case 'science_physics_agent':
        case 'science_chemistry_agent':
        case 'science_biology_agent':
        case 'science_hybrid_agent':
            functions.logger.info('✅ Routing to Science Exercise Agent');
            return scienceExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);

        case 'language_exercise_agent':
        case 'language_english_agent':
        case 'language_spanish_agent':
        case 'language_french_agent':
        case 'language_german_agent':
            functions.logger.info('✅ Routing to Language Exercise Agent');
            return languageExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);

        default:
            // Fallback based on subject
            functions.logger.warn('⚠️  Unknown agent: ' + agentName + ', using fallback routing');

            if (routing.subject.toLowerCase().includes('math')) {
                functions.logger.info('Fallback: Using Math Exercise Agent (based on subject)');
                return mathExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);
            } else if (routing.subject.toLowerCase().includes('science') ||
                       routing.subject.toLowerCase().includes('physics') ||
                       routing.subject.toLowerCase().includes('chemistry') ||
                       routing.subject.toLowerCase().includes('biology')) {
                functions.logger.info('Fallback: Using Science Exercise Agent (based on subject)');
                return scienceExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);
            } else if (routing.subject.toLowerCase().includes('language') ||
                       routing.subject.toLowerCase().includes('english') ||
                       routing.subject.toLowerCase().includes('spanish') ||
                       routing.subject.toLowerCase().includes('french') ||
                       routing.subject.toLowerCase().includes('german')) {
                functions.logger.info('Fallback: Using Language Exercise Agent (based on subject)');
                return languageExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);
            } else {
                // Ultimate fallback - use math exercise agent
                functions.logger.warn('Fallback: Using Math Exercise Agent (default fallback)');
                return mathExerciseAgent(imageBase64, ocrText, ocrBlocks, routing, apiKey);
            }
    }
}

// ============================================================================
// MAIN CLOUD FUNCTION
// ============================================================================

export const analyzeHomeworkAgentic = functions.https.onRequest(async (req, res) => {
    const startTime = Date.now();

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

    functions.logger.info(`✅ App Check token received for agentic analysis`);

    if (isEmulator && appCheckToken === 'emulator-bypass-token') {
        functions.logger.info('🔐 EMULATOR MODE: Using bypass token for agentic analysis');
    }

    // API Key
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        functions.logger.error("GEMINI_API_KEY environment variable not set.");
        res.status(500).send('Server configuration error: API Key missing.');
        return;
    }

    // Input validation
    const { imageBase64, ocrBlocks, userPreferences } = req.body;

    if (!imageBase64 || typeof imageBase64 !== 'string') {
        res.status(400).send('Missing or invalid imageBase64 parameter.');
        return;
    }

    if (!ocrBlocks || !Array.isArray(ocrBlocks)) {
        res.status(400).send('Missing or invalid ocrBlocks parameter.');
        return;
    }

    functions.logger.info('🚀 AGENTIC ANALYSIS: Starting multi-agent workflow');
    functions.logger.info('📊 Request Summary:', {
        ocrBlockCount: ocrBlocks.length,
        hasPreferences: !!userPreferences,
        imageSize: Math.round(imageBase64.length / 1024) + 'KB'
    });

    try {
        functions.logger.info('═══════════════════════════════════════════════════════');
        functions.logger.info('STEP 1: ROUTER AGENT - Classify homework content');
        functions.logger.info('═══════════════════════════════════════════════════════');

        // Step 1: Router Agent - Classify homework
        const ocrText = ocrBlocksToText(ocrBlocks);
        const routing = await routerAgent(imageBase64, ocrText, apiKey);

        functions.logger.info('═══════════════════════════════════════════════════════');
        functions.logger.info('STEP 2: SPECIALIZED AGENT - Detailed analysis');
        functions.logger.info('═══════════════════════════════════════════════════════');

        // Step 2: Specialized Agent - Detailed analysis
        const analysis = await routeToSpecializedAgent(
            routing,
            imageBase64,
            ocrText,
            ocrBlocks,
            apiKey
        );

        functions.logger.info('═══════════════════════════════════════════════════════');
        functions.logger.info('STEP 3: RESPONSE PREPARATION');
        functions.logger.info('═══════════════════════════════════════════════════════');

        // Step 3: Prepare response
        const response = {
            routing: {
                subject: routing.subject,
                contentType: routing.contentType,
                gradeLevel: routing.gradeLevel,
                confidence: routing.confidence,
                agentUsed: routing.recommendedAgent
            },
            analysis,
            metadata: {
                processingTimeMs: Date.now() - startTime,
                agentsInvoked: ['router_agent', routing.recommendedAgent],
                modelVersions: {
                    router: 'gemini-2.5-flash',
                    specialist: 'gemini-2.5-flash'
                },
                timestamp: new Date().toISOString()
            }
        };

        functions.logger.info('✅ AGENTIC ANALYSIS: Complete!');
        functions.logger.info('📈 Final Summary:', {
            totalProcessingTimeMs: response.metadata.processingTimeMs,
            subject: routing.subject,
            contentType: routing.contentType,
            agentUsed: routing.recommendedAgent,
            exercisesFound: analysis.exercises?.length || 0,
            hasStudyMaterial: !!analysis.summary
        });
        functions.logger.info('═══════════════════════════════════════════════════════');

        res.status(200).json(response);

    } catch (error) {
        const err = error as Error;
        const errorTime = Date.now() - startTime;

        functions.logger.error('═══════════════════════════════════════════════════════');
        functions.logger.error('❌ AGENTIC ANALYSIS: FAILED');
        functions.logger.error('═══════════════════════════════════════════════════════');
        functions.logger.error('Error Details:', {
            message: err.message,
            timeBeforeFailure: errorTime + 'ms',
            errorName: err.name,
            stack: err.stack
        });

        res.status(500).json({
            error: 'Homework analysis failed',
            message: err.message,
            processingTimeMs: errorTime
        });
    }
});
