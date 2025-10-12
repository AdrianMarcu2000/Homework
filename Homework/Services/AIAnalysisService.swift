//
//  AIAnalysisService.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import UIKit
import Foundation
import FoundationModels

/// Service for analyzing homework images using Apple's Foundation Models
/// to identify and segment lessons and exercises.
class AIAnalysisService {
    static let shared = AIAnalysisService()

    /// Language model session for AI interactions
    private var session = LanguageModelSession()

    private init() {}

    /// Check if the Foundation Model is available
    var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Represents an OCR text block with its position
    struct OCRBlock: Codable {
        let text: String
        let y: Double
    }

    /// Represents an exercise segment
    struct Exercise: Codable {
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
        let level: Int // 1, 2, or 3
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
        progressHandler: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        // Check if model is available
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        // Step 1: Segment the image based on OCR gaps
        let segments = ImageSegmentationService.shared.segmentImage(
            image: image,
            ocrBlocks: ocrBlocks.map { OCRService.OCRBlock(text: $0.text, y: $0.y) },
            gapThreshold: 0.05
        )

        print("DEBUG SEGMENTATION: Created \(segments.count) initial segments")

        // Merge small segments to avoid over-fragmentation
        let mergedSegments = ImageSegmentationService.shared.mergeSmallSegments(
            segments,
            minSegmentHeight: 0.03,
            fullImage: image
        )

        print("DEBUG SEGMENTATION: After merging: \(mergedSegments.count) segments")

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

RESPONSE FORMAT (choose one):
Exercise: {"type":"exercise","exercise":{"exerciseNumber":"NUM","type":"TYPE","fullContent":"TEXT","startY":\(segment.startY),"endY":\(segment.endY)}}
Skip: {"type":"skip"}

Types: mathematical, multiple_choice, short_answer, essay, fill_in_blanks, true_or_false, matching, calculation, proof, other

---TEXT SEGMENT TO ANALYZE---
\(truncatedText)
---END TEXT SEGMENT---

Return JSON only:
"""

                do {
                    let response = try await session.respond(to: prompt)

                    print("DEBUG: AI Response for segment \(index + 1):")
                    print(response.content)

                    let jsonString = extractJSON(from: response.content)

                    print("DEBUG: Extracted JSON:")
                    print(jsonString)

                    guard let data = jsonString.data(using: .utf8) else {
                        print("DEBUG: Failed to convert JSON to data for segment \(index + 1)")
                        continue
                    }

                    // Parse segment result
                    let segmentResult = try JSONDecoder().decode(SegmentAnalysisResult.self, from: data)

                    print("DEBUG: Segment \(index + 1) - Type: \(segmentResult.type)")

                    if segmentResult.type == "exercise", let exercise = segmentResult.exercise {
                        print("DEBUG: Found exercise #\(exercise.exerciseNumber), Y: \(exercise.startY)-\(exercise.endY)")
                        allExercises.append(exercise)
                    } else {
                        print("DEBUG: Segment skipped (not an exercise)")
                    }
                } catch {
                    print("DEBUG: Error analyzing segment \(index + 1): \(error.localizedDescription)")
                    print("DEBUG: Continuing with remaining segments...")
                    continue
                }
            }

            // Step 3: Combine all results, sorted by Y-position (document order: top to bottom)
            // In Vision coordinates, higher Y = higher on page, so sort DESCENDING for reading order
            let sortedExercises = allExercises.sorted { $0.startY > $1.startY }

            print("DEBUG: Final analysis complete - Exercises: \(allExercises.count)")
            print("DEBUG: Exercise order after sorting (top to bottom):")
            for (idx, ex) in sortedExercises.enumerated() {
                print("  Position \(idx): Exercise #\(ex.exerciseNumber), Y: \(ex.startY)-\(ex.endY)")
            }

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
            "Y: \(String(format: "%.3f", block.y)) - \"\(block.text)\""
        }.joined(separator: "\n")

        let prompt = """
        You are an educational content analyzer specializing in homework exercise identification. Analyze the provided homework page to identify ALL exercises.

        IMPORTANT: Return ONLY valid JSON. Do not include any explanatory text before or after the JSON. Your entire response must be parseable JSON.

        Input Data:
        - Image: A homework page containing exercises
        - OCR text blocks with Y coordinates: "\(ocrBlocksList)"

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
                    "fullContent": "Your cleaned-up and properly formatted understanding of the exercise text, with corrected OCR errors and clear problem statement",
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
        - For fullContent: Provide YOUR interpretation and understanding of the text, not just raw OCR
        - Fix any OCR errors or typos in fullContent
        - Format mathematical expressions clearly in plain text
        - Make the content clear and readable
        - Preserve all important information
        - CRITICAL: Do NOT use any LaTeX notation or backslashes. Write ALL math expressions in plain text only.
        - Use plain text for math: write "x^2" not "x squared in LaTeX", write "x * y" or "x times y" not "x cdot y", write "(a+b)^2" not LaTeX notation.
        - Never use backslash commands like \\(, \\), \\cdot, \\times, \\frac, etc.
        """

        // Use Apple Intelligence to analyze the image with the prompt
        analyzeWithAppleIntelligence(image: image, prompt: prompt) { result in
            switch result {
            case .success(let responseText):
                do {
                    // Extract JSON from the response (in case there's extra text)
                    let jsonString = self.extractJSON(from: responseText)

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

        let prompt = """
        You are an educational exercise generator. Your task is to generate 3 similar practice exercises based on the original exercise provided below. If the exercise has subexercises keep the number of subexercises for each.

        Original Exercise:
        Type: \(exercise.type)
        Content: \(exercise.fullContent)

        Generate exactly 3 exercises with the following difficulty levels:
        1.  **Easier:** A practice exercise that is simpler than the original (e.g., uses smaller numbers, has fewer steps, or is a more basic version of the concept).
        2.  **Same Difficulty:** A practice exercise that has a similar complexity to the original.
        3.  **Harder:** A practice exercise that is more challenging than the original (e.g., uses larger numbers, requires more steps, or introduces a more complex variation of the concept).

        IMPORTANT:
        - Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
        - CRITICAL: Do NOT use any LaTeX notation or backslashes. Write ALL math expressions in plain text only.
        - Use plain text for math: write "x^2" not "x squared in LaTeX", write "x * y" or "x times y" not "x cdot y", write "(a+b)^2" not LaTeX notation.
        - Never use backslash commands like \\(, \\), \\cdot, \\times, \\frac, etc.

        Return a JSON array with this exact structure:
        [
            {
                "exerciseNumber": "1",
                "type": "\(exercise.type)",
                "content": "The exercise text for the 'easier' difficulty level goes here.",
                "difficulty": "same"
            },
            {
                "exerciseNumber": "2",
                "type": "\(exercise.type)",
                "content": "The exercise text for the 'same' difficulty level goes here.",
                "difficulty": "easier"
            },
            {
                "exerciseNumber": "3",
                "type": "\(exercise.type)",
                "content": "The exercise text for the 'harder' difficulty level goes here.",
                "difficulty": "harder"
            }
        ]
        """

        Task {
            do {
                let response = try await session.respond(to: prompt)

                let jsonString = extractJSON(from: response.content)

                guard let data = jsonString.data(using: .utf8) else {
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                let exercises = try decoder.decode([SimilarExercise].self, from: data)

                await MainActor.run {
                    completion(.success(exercises))
                }
            } catch {
                print("ERROR: Parsing similar exercises failed")
                print("Error details: \(error)")
                print("========================")
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
You are an educational content analyzer. Analyze the provided text to identify ALL exercises.

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
- fullContent: Clean, properly formatted text of the exercise with OCR errors corrected
- subject: The subject area (mathematics, language, science, history, etc.) or null if unclear
- inputType: How the student should answer - "text" for written answers, "canvas" for drawing/diagrams, "both" if mixed

IMPORTANT:
- Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
- CRITICAL: Do NOT use any LaTeX notation or backslashes. Write ALL math expressions in plain text only.
- Use plain text for math: write "x^2" not LaTeX, write "x * y" not "x cdot y"
- Never use backslash commands like \\(, \\), \\cdot, \\times, \\frac, etc.

Return a JSON object with this exact structure:
{
    "exercises": [
        {
            "exerciseNumber": "1",
            "type": "mathematical",
            "fullContent": "Solve for x: 2x + 5 = 15",
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

                print("DEBUG TEXT ANALYSIS: AI Response:")
                print(response.content)

                let jsonString = extractJSON(from: response.content)

                print("DEBUG TEXT ANALYSIS: Extracted JSON:")
                print(jsonString)

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

                print("DEBUG TEXT ANALYSIS: Found \(exercises.count) exercises")

                await MainActor.run {
                    completion(.success(finalResult))
                }
            } catch {
                print("DEBUG TEXT ANALYSIS: Error - \(error.localizedDescription)")
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
    ///   - completion: Callback with array of 3 progressive hints
    func generateHints(
        for exercise: Exercise,
        completion: @escaping (Result<[Hint], Error>) -> Void
    ) {
        guard isModelAvailable else {
            completion(.failure(AIAnalysisError.analysisUnavailable))
            return
        }

        let prompt = """
        You are an educational tutor providing progressive hints to help students solve exercises.

        Exercise:
        Type: \(exercise.type)
        Content: \(exercise.fullContent)

        Generate exactly 3 progressive hints to help students solve this exercise. Each hint should reveal more information:

        Level 1: Basic hint - Point the student in the right direction without giving away the method
        Level 2: Method hint - Explain the approach or formula needed, but don't solve it
        Level 3: Detailed hint - Guide through the steps, getting very close to the solution but NOT giving the final answer

        IMPORTANT:
        - Return ONLY valid JSON. Do not include any explanatory text before or after the JSON.
        - CRITICAL: Do NOT use any LaTeX notation or backslashes. Write ALL math expressions in plain text only.
        - Use plain text for math: write "x^2" not "x squared in LaTeX", write "x * y" or "x times y" not "x cdot y", write "(a+b)^2" not LaTeX notation.
        - Never use backslash commands like \\(, \\), \\cdot, \\times, \\frac, etc.

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
                "content": "Explain the approach or formula needed"
            },
            {
                "level": 3,
                "title": "Step-by-Step Guide",
                "content": "Walk through the process without giving the final answer"
            }
        ]

        Guidelines:
        - Be encouraging and supportive in tone
        - Each hint should be progressively more detailed
        - Never give away the final answer directly
        - Use clear, student-friendly language
        - Tailor the complexity to the exercise type
        """

        Task {
            do {
                let response = try await session.respond(to: prompt)
                let jsonString = extractJSON(from: response.content)

                guard let data = jsonString.data(using: .utf8) else {
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                let hints = try decoder.decode([Hint].self, from: data)

                await MainActor.run {
                    completion(.success(hints))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(AIAnalysisError.parsingFailed(error)))
                }
            }
        }
    }

    /// Extracts JSON from a response that might contain additional text
    private func extractJSON(from text: String) -> String {
        var jsonString = text

        // Remove markdown code blocks if present (```json ... ``` or ``` ... ```)
        var cleanedText = text
        if let codeBlockStart = text.range(of: "```json\n"),
           let codeBlockEnd = text.range(of: "\n```", range: codeBlockStart.upperBound..<text.endIndex) {
            cleanedText = String(text[codeBlockStart.upperBound..<codeBlockEnd.lowerBound])
        } else if let codeBlockStart = text.range(of: "```\n"),
                  let codeBlockEnd = text.range(of: "\n```", range: codeBlockStart.upperBound..<text.endIndex) {
            cleanedText = String(text[codeBlockStart.upperBound..<codeBlockEnd.lowerBound])
        }

        // Trim whitespace and check what the JSON starts with
        let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it starts with [ (array) or { (object) to determine what to extract
        if trimmed.hasPrefix("[") {
            // Extract array
            if let startIndex = cleanedText.firstIndex(of: "["),
               let endIndex = cleanedText.lastIndex(of: "]") {
                let jsonRange = startIndex...endIndex
                jsonString = String(cleanedText[jsonRange])
            }
        } else if trimmed.hasPrefix("{") {
            // Extract object
            if let startIndex = cleanedText.firstIndex(of: "{"),
               let endIndex = cleanedText.lastIndex(of: "}") {
                let jsonRange = startIndex...endIndex
                jsonString = String(cleanedText[jsonRange])
            }
        } else {
            // Fallback: try to find any JSON structure in cleaned text
            // Try object first
            if let startIndex = cleanedText.firstIndex(of: "{"),
               let endIndex = cleanedText.lastIndex(of: "}") {
                let jsonRange = startIndex...endIndex
                jsonString = String(cleanedText[jsonRange])
            }
            // Try array
            else if let startIndex = cleanedText.firstIndex(of: "["),
                    let endIndex = cleanedText.lastIndex(of: "]") {
                let jsonRange = startIndex...endIndex
                jsonString = String(cleanedText[jsonRange])
            }
        }

        // Fix LaTeX math notation and other backslash issues in JSON
        // Replace single backslashes with double backslashes for proper JSON escaping
        jsonString = jsonString.replacingOccurrences(of: "\\(", with: "\\\\(")
        jsonString = jsonString.replacingOccurrences(of: "\\)", with: "\\\\)")
        jsonString = jsonString.replacingOccurrences(of: "\\[", with: "\\\\[")
        jsonString = jsonString.replacingOccurrences(of: "\\]", with: "\\\\]")
        jsonString = jsonString.replacingOccurrences(of: "\\times", with: "\\\\times")
        jsonString = jsonString.replacingOccurrences(of: "\\cdot", with: "\\\\cdot")
        jsonString = jsonString.replacingOccurrences(of: "\\frac", with: "\\\\frac")
        jsonString = jsonString.replacingOccurrences(of: "\\sqrt", with: "\\\\sqrt")
        jsonString = jsonString.replacingOccurrences(of: "\\div", with: "\\\\div")
        jsonString = jsonString.replacingOccurrences(of: "\\pm", with: "\\\\pm")
        jsonString = jsonString.replacingOccurrences(of: "\\leq", with: "\\\\leq")
        jsonString = jsonString.replacingOccurrences(of: "\\geq", with: "\\\\geq")
        jsonString = jsonString.replacingOccurrences(of: "\\neq", with: "\\\\neq")
        jsonString = jsonString.replacingOccurrences(of: "\\approx", with: "\\\\approx")

        return jsonString
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
                // Send the prompt to the Foundation Model
                let response = try await session.respond(to: prompt)

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
