//
//  AIAnalysisService.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import UIKit
import Foundation
import FoundationModels
import OSLog

/// Service for analyzing homework images using Apple's Foundation Models
/// to identify and segment lessons and exercises.
class AIAnalysisService {
    static let shared = AIAnalysisService()

    /// Language model session for AI interactions
    private var session = LanguageModelSession()

    private init() {}

    /// Check if the Foundation Model is available
    /// Returns true only on devices that genuinely support Apple Intelligence
    var isModelAvailable: Bool {
        // Check the system's reported availability
        return SystemLanguageModel.default.isAvailable
    }

    /// Represents an OCR text block with its position
    struct OCRBlock: Codable {
        let text: String
        let y: Double
    }

    /// Represents an exercise segment
    struct Exercise: Codable, Hashable {
        let exerciseNumber: String
        let type: String
        let fullContent: String
        let startY: Double
        let endY: Double
        let subject: String? // mathematics, language, science, history, etc.
        let inputType: String? // text, canvas, both

        // Custom decoding to handle null exerciseNumber and optional fields
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // If exerciseNumber is null, use "Unknown"
            if let number = try container.decodeIfPresent(String.self, forKey: .exerciseNumber) {
                self.exerciseNumber = number
            } else {
                self.exerciseNumber = "Unknown"
            }

            self.type = try container.decode(String.self, forKey: .type)
            self.fullContent = try container.decode(String.self, forKey: .fullContent)
            self.startY = try container.decode(Double.self, forKey: .startY)
            self.endY = try container.decode(Double.self, forKey: .endY)
            self.subject = try container.decodeIfPresent(String.self, forKey: .subject)
            self.inputType = try container.decodeIfPresent(String.self, forKey: .inputType) ?? "canvas" // default to canvas
        }

        // Regular init for non-decoded creation
        init(exerciseNumber: String, type: String, fullContent: String, startY: Double, endY: Double, subject: String? = nil, inputType: String? = "canvas") {
            self.exerciseNumber = exerciseNumber
            self.type = type
            self.fullContent = fullContent
            self.startY = startY
            self.endY = endY
            self.subject = subject
            self.inputType = inputType
        }

        enum CodingKeys: String, CodingKey {
            case exerciseNumber, type, fullContent, startY, endY, subject, inputType
        }
    }

    /// Analysis result containing exercises
    struct AnalysisResult: Codable {
        let exercises: [Exercise]
    }

    /// Result from analyzing a single segment
    private struct SegmentAnalysisResult: Codable {
        let type: String // "exercise" or "skip"
        let exercise: Exercise?
    }

    /// Generated similar exercise
    struct SimilarExercise: Codable, Identifiable {
        var id: UUID { UUID() }
        let exerciseNumber: String
        let type: String
        let content: String
        let difficulty: String // same, easier, harder

        enum CodingKeys: String, CodingKey {
            case exerciseNumber, type, content, difficulty
        }
    }

    /// Progressive hint for an exercise
    struct Hint: Codable, Identifiable {
        var id: UUID { UUID() }
        let level: Int // 1, 2, 3 or 4
        let title: String
        let content: String

        enum CodingKeys: String, CodingKey {
            case level, title, content
        }
    }

    /// Analyzes a homework image using segment-based approach with text analysis
    ///
    /// - Parameters:
    ///   - image: The homework page image
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates
    ///   - progressHandler: Optional callback for progress updates (current, total)
    ///   - completion: Callback with the analysis result or error
    func analyzeHomeworkWithSegments(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> Result<AnalysisResult, Error> {
        return await withCheckedContinuation { continuation in
            analyzeHomeworkWithSegments(image: image, ocrBlocks: ocrBlocks, progressHandler: progressHandler) { result in
                continuation.resume(returning: result)
            }
        }
    }

    func analyzeHomeworkWithSegments(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        progressHandler: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {

        // Step 1: Segment the image based on OCR gaps
        let segments = ImageSegmentationService.shared.segmentImage(
            image: image,
            ocrBlocks: ocrBlocks.map { OCRService.OCRBlock(text: $0.text, y: $0.y) },
            gapThreshold: 0.05
        )

        // Merge small segments to avoid over-fragmentation
        let mergedSegments = ImageSegmentationService.shared.mergeSmallSegments(
            segments,
            minSegmentHeight: 0.03,
            fullImage: image
        )

        AppLogger.ai.info("Segmented image into \(mergedSegments.count) sections for analysis")

        guard !mergedSegments.isEmpty else {
            completion(.failure(AIAnalysisError.parsingFailed(NSError(
                domain: "AIAnalysis",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No segments found"]
            ))))
            return
        }

        // Build condensed page context (just Y-coordinate ranges to avoid context overflow)
        let _ = mergedSegments.enumerated().map { index, seg in
            "Segment \(index + 1): Y \(String(format: "%.3f", seg.startY)) - \(String(format: "%.3f", seg.endY))"
        }.joined(separator: "\n")

        // Step 2: Analyze each segment with text-based context
        Task {
            var allExercises: [Exercise] = []

            let totalSegments = mergedSegments.count

            for (index, segment) in mergedSegments.enumerated() {
                // Report progress
                await MainActor.run {
                    progressHandler?(index + 1, totalSegments)
                }

                // Create segment OCR text (truncate if too long to avoid context window issues)
                let segmentOCRText = segment.ocrBlocks.map { $0.text }.joined(separator: "\n")
                let truncatedText = segmentOCRText.count > 1000 ? String(segmentOCRText.prefix(1000)) + "..." : segmentOCRText

                let prompt = """
INSTRUCTIONS:
Determine if the TEXT SEGMENT below is an exercise. Return ONLY JSON, no explanations.

RULES:
- Numbered items (1., 2., a., b., etc.) = EXERCISE
- Questions or imperatives (Find, Solve, Calculate, Write, Complete, Expand) = EXERCISE
- Pure headers/footers/titles without questions = SKIP

LATEX FORMATTING FOR fullContent:
- For chemical formulas use proper LaTeX: CO\\textsubscript{2} or \\ce{CO2}
- For math expressions use: \\(expression\\) for inline, \\[expression\\] for block
- For subscripts: H\\textsubscript{2}O or \\(H_2O\\)
- For superscripts: cm\\textsuperscript{3} or \\(cm^3\\)
- CRITICAL: Include the backslash! Write \\textsubscript NOT textsubscript
- Examples: "Atmosphere (\\ce{CO2})" or "Temperature (°C)"

RESPONSE FORMAT:
You must respond with a JSON object that has a "type" field.
If the segment is an exercise, the JSON should be:
{\"type\":\"exercise\", \"exercise\": {\"exerciseNumber\":\"NUM\", \"type\":\"TYPE\", \"fullContent\":\"TEXT\", \"startY\":\(segment.startY), \"endY\":\(segment.endY)}}

If the segment should be skipped, the JSON should be:
{\"type\":\"skip\"}

Types: mathematical, multiple_choice, short_answer, essay, fill_in_blanks, true_or_false, matching, calculation, proof, other

IMPORTANT: In fullContent, fix OCR errors and format chemical/math notation properly with LaTeX commands including backslashes.

---TEXT SEGMENT TO ANALYZE---
\(truncatedText)
---END TEXT SEGMENT---

Return ONLY the JSON object:
"""

                do {
                    let response = try await session.respond(to: prompt)

                    var jsonString = response.content

                    // Remove markdown code block wrapper if present
                    jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if jsonString.hasPrefix("```json") {
                        jsonString = String(jsonString.dropFirst(7)) // Remove ```json
                    }
                    if jsonString.hasPrefix("```") {
                        jsonString = String(jsonString.dropFirst(3)) // Remove ```
                    }
                    if jsonString.hasSuffix("```") {
                        jsonString = String(jsonString.dropLast(3)) // Remove trailing ```
                    }
                    jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard let data = jsonString.data(using: .utf8) else {
                        AppLogger.ai.error("Failed to convert JSON to data for segment \(index + 1)")
                        continue
                    }

                    // Parse segment result
                    let segmentResult = try JSONDecoder().decode(SegmentAnalysisResult.self, from: data)

                    if segmentResult.type == "exercise", let exercise = segmentResult.exercise {
                        AppLogger.ai.info("Found exercise #\(exercise.exerciseNumber) at Y: \(exercise.startY)-\(exercise.endY)")
                        allExercises.append(exercise)
                    }
                } catch {
                    AppLogger.ai.error("Error analyzing segment \(index + 1)", error: error)
                    AppLogger.ai.info("Continuing with remaining segments...")
                    continue
                }
            }

            // Step 3: Combine all results, sorted by Y-position (document order: top to bottom)
            // In Vision coordinates, higher Y = higher on page, so sort DESCENDING for reading order
            let sortedExercises = allExercises.sorted { $0.startY > $1.startY }

            AppLogger.ai.info("Analysis complete with \(allExercises.count) exercises identified")

            let finalResult = AnalysisResult(
                exercises: sortedExercises
            )

            await MainActor.run {
                completion(.success(finalResult))
            }
        }
    }

    /// Original homework analysis method (fallback)
    ///
    /// - Parameters:
    ///   - image: The homework page image
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates
    ///   - completion: Callback with the analysis result or error
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        // Check for Apple Intelligence availability (iOS 18.1+)
        guard #available(iOS 18.1, *) else {
            completion(.failure(AIAnalysisError.unsupportedVersion))
            return
        }

        // Format OCR blocks for the prompt
        let ocrBlocksList = ocrBlocks.map { block in
            "Y: \\(String(format: \"%.3f\", block.y)) - \"\(block.text)\""
        }.joined(separator: "\n")

        let prompt = """
        You are a helpful assistant that is an expert in LaTeX and always returns valid LaTeX. You are an educational content analyzer specializing in homework exercise identification. Analyze the provided homework page to identify ALL exercises.

        IMPORTANT: Return ONLY valid JSON. Do not include any explanatory text before or after the JSON. Your entire response must be parseable JSON.

        Input Data:
        - Image: A homework page containing exercises
        - OCR text blocks with Y coordinates: \"\(ocrBlocksList)\" 

        Core Classification Rules:

        EXERCISE (tasks for students):
        - Questions, problems, or tasks that ASK the student to do something
        - Must have BOTH identifier (number/letter) AND task body
        - Problems WITHOUT solutions (blank spaces for student responses)
        - Contains question words: "Find", "Calculate", "Solve", "Show", "Prove", "Determine"
        - Contains instruction words: "Complete", "Fill in", "Draw", "Explain", "Expand", "Write"
        - Contains question marks (?) or imperative verbs
        - Numbered items (1., 2., a., b., etc.)
        - When the text contains multiple paragraphs, separate the exercises

        SKIP (not exercises):
        - Pure page headers, footers, page numbers
        - Section titles without actual questions
        - A heading alone (e.g., "Exercise 1" with no task) is NOT an exercise

        CRITICAL: For each identified exercise, determine both START and END positions:
        - startY: Y coordinate where the exercise begins (from the first relevant OCR block)
        - endY: Y coordinate where the exercise ends (from the last relevant OCR block)

        Use the OCR block Y coordinates to precisely determine where each exercise starts and ends. Look for:
        - Natural content boundaries (blank lines, new headings, different formatting)
        - Sequential exercise numbering to determine where one exercise ends and another begins

        Return a JSON object with this exact structure:
        {
            "exercises": [
                {
                    "exerciseNumber": "1",
                    "type": "mathematical",
                    "fullContent": "Solve the following equation: \\(x^2 + 2x + 1 = 0\\)",
                    "startY": 0.300,
                    "endY": 0.420
                }
            ]
        }

        Exercise types: mathematical, multiple_choice, short_answer, essay, fill_in_blanks, true_or_false, matching, calculation, proof, diagram, other

        IMPORTANT:
        - Use precise Y coordinates from the OCR blocks
        - Ensure endY > startY for each item
        - Do not overlap content boundaries
        - For fullContent: Provide YOUR interpretation and understanding of the text, not just raw OCR. When creating the `fullContent`, it is crucial that you preserve the original formatting and indentation of the exercise as seen in the image. This includes line breaks, spacing, and any other structural elements.
        - Fix any OCR errors or typos in fullContent
        - Make the content clear and readable
        - CRITICAL: Pay close attention to the LaTeX formatting. For all mathematical content, you MUST use LaTeX notation.
        - Enclose inline math expressions with \\( and \\).
        - Enclose block math expressions with \\[ and \\].
        - For example: \\(x^2 + y^2 = r^2\\) or \\[\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\\\\]
        - Ensure all backslashes in LaTeX are properly escaped for JSON output (e.g., \\\\(x^2\\\\) becomes \\\\\\\\(x^2\\\\\\\\) in the final JSON string).
        """

        // Use Apple Intelligence to analyze the image with the prompt
        analyzeWithAppleIntelligence(image: image, prompt: prompt) { result in
            switch result {
            case .success(let responseText):
                do {
                    // Extract JSON from the response (in case there's extra text)
                    let jsonString = responseText

                    // Parse the JSON response
                    guard let data = jsonString.data(using: .utf8) else {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data"]))))
                        return
                    }

                    let decoder = JSONDecoder()
                    var analysisResult = try decoder.decode(AnalysisResult.self, from: data)

                    // Sort by Y-position to maintain document order (top to bottom)
                    // In Vision coordinates, higher Y = higher on page, so sort DESCENDING
                    analysisResult = AnalysisResult(
                        exercises: analysisResult.exercises.sorted { $0.startY > $1.startY }
                    )

                    completion(.success(analysisResult))
                } catch {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Generates similar test exercises based on an existing exercise
    ///
    /// - Parameters:
    ///   - exercise: The original exercise to base similar exercises on
    ///   - count: Number of similar exercises to generate (default: 3)
    ///   - completion: Callback with array of generated exercises
    func generateSimilarExercises(
        basedOn exercise: Exercise,
        count: Int = 3,
        completion: @escaping (Result<[SimilarExercise], Error>) -> Void
    ) {
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        // Reset session to clear any accumulated context
        session = LanguageModelSession()

        let prompt = """
        You are a helpful assistant that is an expert in LaTeX and always returns valid LaTeX. You are an educational exercise generator. Your task is to generate 3 similar practice exercises based on the original exercise provided below. If the exercise has subexercises keep the number of subexercises for each.

        Original Exercise:
        Type: \(exercise.type)
        Content: \(exercise.fullContent)

        Generate exactly 3 exercises with the following difficulty levels:
        1.  **Easier:** A practice exercise that is simpler than the original (e.g., uses smaller numbers, has fewer steps, or is a more basic version of the concept).
        2.  **Same Difficulty:** A practice exercise that has a similar complexity to the original.
        3.  **Harder:** A practice exercise that is more challenging than the original (e.g., uses larger numbers, requires more steps, or introduces a more complex variation of the concept).

        IMPORTANT:
        - Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
        - CRITICAL: Pay close attention to the LaTeX formatting. For all mathematical content, you MUST use LaTeX notation.
        - Enclose inline math expressions with \\( and \\).
        - Enclose block math expressions with \\[ and \\].
        - Ensure all backslashes in LaTeX are properly escaped for JSON output (e.g., \\\\(x^2\\\\) becomes \\\\\\\\(x^2\\\\\\\\) in the final JSON string).

        Return a JSON array with this exact structure:
        [
            {
                "exerciseNumber": "1",
                "type": \"\(exercise.type)\"",
                "content": "The exercise text for the 'easier' difficulty level goes here.",
                "difficulty": "same"
            },
            {
                "exerciseNumber": "2",
                "type": \"\(exercise.type)\"",
                "content": "The exercise text for the 'same' difficulty level goes here.",
                "difficulty": "easier"
            },
            {
                "exerciseNumber": "3",
                "type": \"\(exercise.type)\"",
                "content": "The exercise text for the 'harder' difficulty level goes here.",
                "difficulty": "harder"
            }
        ]
        """

        Task {
            do {
                let response = try await session.respond(to: prompt)

                let jsonString = response.content

                guard let data = jsonString.data(using: .utf8) else {
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                let exercises = try decoder.decode([SimilarExercise].self, from: data)

                AppLogger.ai.info("Generated \(exercises.count) similar exercises")
                await MainActor.run {
                    completion(.success(exercises))
                }
            } catch {
                AppLogger.ai.error("Failed to generate similar exercises", error: error)
                await MainActor.run {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            }
        }
    }

    /// Analyzes text-only homework (no image) to identify and extract exercises
    ///
    /// - Parameters:
    ///   - text: The homework text to analyze
    ///   - completion: Callback with the analysis result or error
    func analyzeTextOnly(
        text: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        let prompt = """
INSTRUCTIONS:
You are a helpful assistant that is an expert in LaTeX and always returns valid LaTeX. You are an educational content analyzer. Analyze the provided text to identify ALL exercises.

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
- type: Choose from: mathematical, multiple_choice, short_answer, essay, fill_in_blanks, true_or_false, matching, calculation, proof, other
- fullContent: Clean, properly formatted text of the exercise with OCR errors corrected. When creating the `fullContent`, it is crucial that you preserve the original formatting and indentation of the exercise as seen in the image. This includes line breaks, spacing, and any other structural elements.
- subject: The subject area (mathematics, language, science, history, etc.) or null if unclear
- inputType: How the student should answer - "text" for written answers, "canvas" for drawing/diagrams, "both" if mixed

IMPORTANT:
- Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
- CRITICAL: Pay close attention to the LaTeX formatting. For all mathematical content, you MUST use LaTeX notation.
- Enclose inline math expressions with \\( and \\).
- Enclose block math expressions with \\[ and \\].
- Ensure all backslashes in LaTeX are properly escaped for JSON output (e.g., \\\\(x^2\\\\) becomes \\\\\\\\(x^2\\\\\\\\) in the final JSON string).

Return a JSON object with this exact structure:
{
    "exercises": [
        {
            "exerciseNumber": "1",
            "type": "mathematical",
            "fullContent": "Solve for x: \\(2x + 5 = 15\\)",
            "subject": "mathematics",
            "inputType": "text"
        }
    ]
}

---TEXT TO ANALYZE---
\(text)
---END TEXT---

Return ONLY valid JSON:
"""

        Task {
            do {
                let response = try await session.respond(to: prompt)

                let jsonString = response.content

                guard let data = jsonString.data(using: .utf8) else {
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                // Parse the response - but it won't have Y coordinates
                // We need to handle this by adding fake Y coordinates for compatibility
                struct TextAnalysisResult: Codable {
                    let exercises: [TextExercise]
                }

                struct TextExercise: Codable {
                    let exerciseNumber: String
                    let type: String
                    let fullContent: String
                    let subject: String?
                    let inputType: String?
                }

                let decoder = JSONDecoder()
                let textResult = try decoder.decode(TextAnalysisResult.self, from: data)

                // Convert to Exercise format with fake Y coordinates
                let exercises = textResult.exercises.enumerated().map { index, textEx in
                    let yPosition = Double(index) * 0.1
                    return Exercise(
                        exerciseNumber: textEx.exerciseNumber,
                        type: textEx.type,
                        fullContent: textEx.fullContent,
                        startY: yPosition,
                        endY: yPosition + 0.05,
                        subject: textEx.subject,
                        inputType: textEx.inputType ?? "text"
                    )
                }

                let finalResult = AnalysisResult(exercises: exercises)

                AppLogger.ai.info("Text-only analysis found \(exercises.count) exercises")

                await MainActor.run {
                    completion(.success(finalResult))
                }
            } catch {
                AppLogger.ai.error("Text-only analysis failed", error: error)
                await MainActor.run {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            }
        }
    }

    /// Generates a concise summary of the homework analysis
    ///
    /// - Parameters:
    ///   - analysisResult: The analysis result containing exercises
    ///   - completion: Callback with the summary text
    func generateHomeworkSummary(
        for analysisResult: AnalysisResult,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        // Reset session to clear any accumulated context
        session = LanguageModelSession()

        // Build a description of the content
        let exercisesDesc = analysisResult.exercises.map { "- Exercise \($0.exerciseNumber): \($0.type)" }.joined(separator: "\n")

        let prompt = """
INSTRUCTIONS:
Generate a brief, student-friendly summary (1-2 sentences) of this homework page.

CONTENT FOUND:
Exercises (\(analysisResult.exercises.count)):
\(exercisesDesc.isEmpty ? "None" : exercisesDesc)

Return ONLY the summary text, no JSON, no formatting. Be concise and helpful.
"""

        Task {
            do {
                let response = try await session.respond(to: prompt)
                let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    completion(.success(summary))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Generates progressive hints for an exercise
    ///
    /// - Parameters:
    ///   - exercise: The exercise to generate hints for
    ///   - completion: Callback with array of 4 progressive hints
    func generateHints(
        for exercise: Exercise,
        completion: @escaping (Result<[Hint], Error>) -> Void
    ) {
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        // Reset session to clear any accumulated context
        session = LanguageModelSession()

        let prompt = """
        You are an educational tutor providing progressive hints to help students solve exercises.

        Exercise:
        Type: \(exercise.type)
        Content: \(exercise.fullContent)

        IMPORTANT: If this exercise has multiple sub-parts (like a, b, c or 1, 2, 3), address ALL parts in each hint level.

        Generate exactly 4 progressive hints to help students solve this exercise. Each hint should reveal more information:

        Level 1: Basic hint - Point the student in the right direction for ALL parts without giving away the method
        Level 2: Method hint - Explain the approach or formula needed for EACH part, but don't solve
        Level 3: Detailed hint - Guide through the steps for EACH part, getting very close to the solution but NOT giving final answers
        Level 4: Complete answer - Provide the full solution for ALL parts with clear explanations

        MATHEMATICAL NOTATION RULES:
        - Use inline LaTeX \\\\(expression\\\\) for mathematical expressions
        - Examples: \\\\(x^2 + 5\\\\), \\\\(\\frac{a}{b}\\\\), \\\\(2\\pi r\\\\)
        - Use block LaTeX \\\\[expression\\\\] for important standalone equations
        - DO NOT nest LaTeX delimiters: WRONG: \\\\(x = \\\\(5\\\\)\\\\), CORRECT: \\\\(x = 5\\\\)
        - DO NOT put plain text or names in math mode: WRONG: \\\\(Monday\\\\), CORRECT: Monday
        - For lists, write normally: "Monday, Tuesday, Wednesday" not "\\\\(Monday, Tuesday, Wednesday\\\\)"

        UNITS IN LATEX:
        - For units with values, use \\\\text{} for the unit part
        - WRONG: \\\\(8\\\\ g/cm^3\\\\) - backslash-space creates line break
        - CORRECT: \\\\(8\\\\text{ g/cm}^3\\\\) - use \\\\text{} for units
        - CORRECT: \\\\(8 \\\\, \\\\text{g/cm}^3\\\\) - use \\\\, for thin space
        - Examples: \\\\(5\\\\text{ kg}\\\\), \\\\(20\\\\text{ m/s}\\\\), \\\\(8\\\\text{ g/cm}^3\\\\)
        - Outside math mode, write units normally: "The density is 8 g/cm³" (use Unicode) or "8 g/cm^3"

        LATEX CODE FOR VISUALIZATIONS:
        - You MAY include LaTeX/TikZ code in level 4 for charts, diagrams, graphs
        - CRITICAL TikZ RULES:
          * Coordinates are 2D positions with LINEAR dimensions: (1,2) or (1cm,2cm)
          * NEVER use volume/area units (cm^3, cm^2, m^3) in coordinates - these aren't positions!
          * WRONG: (1cm, 8cm^3) - cm^3 is volume, not a coordinate
          * CORRECT: (1cm, 2cm) - both are linear dimensions
          * For volumes/areas, show them as LABELS using \\\\node, not coordinates
          * Example: \\\\node at (1,1) {Volume: \\\\(8\\\\text{ cm}^3\\\\)};
          * Keep TikZ code simple and syntactically valid
        - Ensure ALL backslashes in LaTeX code are DOUBLE-escaped for JSON
        - Example: "\\\\begin{tikzpicture} \\\\draw (0,0) rectangle (2cm,3cm); \\\\node at (1cm,1.5cm) {Label}; \\\\end{tikzpicture}"
        - Separate explanation text from code
        - If the problem involves volumes or 3D objects, either:
          * Draw a 2D projection and label it with the volume
          * Describe the visualization in words instead of attempting 3D TikZ
          * Use simple 2D shapes with annotations

        CRITICAL JSON FORMATTING:
        - Return ONLY valid JSON. Do not wrap in markdown code blocks (no ```json or ```)
        - ALL backslashes must be double-escaped: single \\\\ becomes \\\\\\\\
        - Newlines in content are fine but must be actual line breaks, not \\\\n
        - Test your JSON is valid before responding

        Return a JSON array with this exact structure:
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
                "content": "Full solution with LaTeX/TikZ if needed. Example: Draw a circle: \\\\begin{tikzpicture} \\\\draw (0,0) circle (1cm); \\\\end{tikzpicture}"
            }
        ]

        MULTI-PART EXERCISE STRUCTURE:
        If exercise has parts like "a) Find x, b) Calculate y, c) Prove z", structure hints as:
        Level 1: "For part a: [hint]. For part b: [hint]. For part c: [hint]."
        Level 2: "Part a: Use [method]. Part b: Apply [approach]. Part c: Consider [strategy]."
        Level 3: "Part a: Step 1... Step 2... Part b: First... Then... Part c: Begin by..."
        Level 4: "Part a: [complete solution]. Part b: [complete solution]. Part c: [complete solution]."

        Guidelines:
        - Be encouraging and supportive
        - Each hint progressively more detailed
        - Use clear, student-friendly language
        - Proper LaTeX syntax with correct escaping
        - Avoid nested delimiters and plain text in math mode
        - For multi-part exercises, address every sub-part in every hint level
        """

        Task {
            do {
                AppLogger.ai.info("Generating hints for exercise: \(exercise.exerciseNumber)")

                let response = try await session.respond(to: prompt)

                var jsonString = response.content

                // Remove markdown code block wrapper if present
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasPrefix("```json") {
                    jsonString = String(jsonString.dropFirst(7)) // Remove ```json
                }
                if jsonString.hasPrefix("```") {
                    jsonString = String(jsonString.dropFirst(3)) // Remove ```
                }
                if jsonString.hasSuffix("```") {
                    jsonString = String(jsonString.dropLast(3)) // Remove trailing ```
                }
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

                // Sanitize LaTeX in JSON - fix improperly escaped backslashes
                jsonString = sanitizeLaTeXInJSON(jsonString)

                guard let data = jsonString.data(using: .utf8) else {
                    AppLogger.ai.error("Failed to convert JSON string to data")
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data"]))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                do {
                    let hints = try decoder.decode([Hint].self, from: data)
                    AppLogger.ai.info("Successfully generated \(hints.count) hints")

                    await MainActor.run {
                        completion(.success(hints))
                    }
                } catch let decodingError as DecodingError {
                    AppLogger.ai.error("Hint decoding error")
                    switch decodingError {
                    case .dataCorrupted(let context):
                        AppLogger.ai.error("  - Data corrupted: \(context.debugDescription)")
                    case .keyNotFound(let key, let context):
                        AppLogger.ai.error("  - Key not found: \(key.stringValue) - \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        AppLogger.ai.error("  - Type mismatch: expected \(type) - \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        AppLogger.ai.error("  - Value not found: \(type) - \(context.debugDescription)")
                    @unknown default:
                        AppLogger.ai.error("  - Unknown decoding error", error: decodingError)
                    }

                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(decodingError)))
                    }
                } catch {
                    AppLogger.ai.error("Non-decoding error during hint generation", error: error)
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(error)))
                    }
                }
            } catch {
                AppLogger.ai.error("Error generating hints", error: error)
                await MainActor.run {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            }
        }
    }

    /// Sanitizes LaTeX notation in JSON strings by properly escaping backslashes and newlines
    /// This fixes common issues where AI models don't properly escape LaTeX in JSON
    private func sanitizeLaTeXInJSON(_ json: String) -> String {
        // Simpler approach: build result string piece by piece
        var result = ""
        var currentIndex = json.startIndex

        // Pattern to match "content": "..." with proper handling of escaped quotes
        let pattern = #"("content"\s*:\s*")([^"]*(?:\\.[^"]*)*)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            AppLogger.ai.error("Failed to create regex for JSON sanitization")
            return json
        }

        let nsRange = NSRange(json.startIndex..., in: json)
        let matches = regex.matches(in: json, options: [], range: nsRange)

        for match in matches {
            guard match.numberOfRanges == 3,
                  let prefixRange = Range(match.range(at: 1), in: json),
                  let contentRange = Range(match.range(at: 2), in: json) else {
                continue
            }

            // Append everything before this match
            result += json[currentIndex..<prefixRange.lowerBound]

            // Append the prefix ("content": ")
            result += json[prefixRange]

            // Process the content
            let content = String(json[contentRange])
            let sanitized = sanitizeJSONContent(content)
            result += sanitized

            // Update current index to after the content (the closing quote is not in the match)
            currentIndex = contentRange.upperBound
        }

        // Append remaining string
        result += json[currentIndex...]

        return result
    }

    /// Sanitizes a single content value for JSON
    private func sanitizeJSONContent(_ content: String) -> String {
        var result = content

        // Step 1: Escape literal newlines and carriage returns
        result = result
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")

        // Step 2: Fix backslashes
        // Protect already-escaped sequences
        let protected = result
            .replacingOccurrences(of: "\\\\", with: "\u{0001}DBLSLASH\u{0001}")
            .replacingOccurrences(of: "\\n", with: "\u{0001}NEWLINE\u{0001}")
            .replacingOccurrences(of: "\\t", with: "\u{0001}TAB\u{0001}")
            .replacingOccurrences(of: "\\r", with: "\u{0001}RETURN\u{0001}")
            .replacingOccurrences(of: "\\\"", with: "\u{0001}QUOTE\u{0001}")
            .replacingOccurrences(of: "\\'", with: "\u{0001}APOS\u{0001}")

        // Replace remaining single backslashes with double
        let fixed = protected.replacingOccurrences(of: "\\", with: "\\\\")

        // Restore protected sequences
        var restored = fixed
            .replacingOccurrences(of: "\u{0001}DBLSLASH\u{0001}", with: "\\\\")
            .replacingOccurrences(of: "\u{0001}NEWLINE\u{0001}", with: "\\n")
            .replacingOccurrences(of: "\u{0001}TAB\u{0001}", with: "\\t")
            .replacingOccurrences(of: "\u{0001}RETURN\u{0001}", with: "\\r")
            .replacingOccurrences(of: "\u{0001}QUOTE\u{0001}", with: "\\\"")
            .replacingOccurrences(of: "\u{0001}APOS\u{0001}", with: "\\'")

        // Step 3: Fix trailing backslashes that would escape the closing quote
        var trailingBackslashes = 0
        for char in restored.reversed() {
            if char == "\\" {
                trailingBackslashes += 1
            } else {
                break
            }
        }
        // If odd number of trailing backslashes, add one more
        if trailingBackslashes % 2 == 1 {
            restored += "\\"
        }

        return restored
    }

    /// Performs AI analysis using Apple Intelligence Foundation Models
    private func analyzeWithAppleIntelligence(
        image: UIImage,
        prompt: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Check if model is available
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        // Perform analysis asynchronously
        Task {
            do {
                // Create a prompt with both text and image
                let multimodalPrompt = Prompt {
                    prompt
                }

                // Send the prompt with image to the Foundation Model
                let response = try await session.respond(to: multimodalPrompt)

                // Extract the content from the response
                let jsonContent = response.content

                // Return on main thread
                await MainActor.run {
                    completion(.success(jsonContent))
                }
            } catch {
                // Handle errors
                await MainActor.run {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            }
        }
    }

    /// Errors that can occur during AI analysis
    enum AIAnalysisError: LocalizedError {
        case unsupportedVersion
        case parsingFailed(Error)
        case analysisUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "Apple Intelligence requires iOS 18.1 or later"
            case .parsingFailed(let error):
                return "Failed to parse analysis result: \(error.localizedDescription)"
            case .analysisUnavailable:
                return "Apple Intelligence is not available on this device"
            }
        }
    }
}
