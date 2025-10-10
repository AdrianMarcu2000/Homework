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

    /// Represents a lesson segment
    struct Lesson: Codable {
        let topic: String
        let fullContent: String
        let startY: Double
        let endY: Double
    }

    /// Represents an exercise segment
    struct Exercise: Codable {
        let exerciseNumber: String
        let type: String
        let fullContent: String
        let startY: Double
        let endY: Double

        // Custom decoding to handle null exerciseNumber
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
        }

        // Regular init for non-decoded creation
        init(exerciseNumber: String, type: String, fullContent: String, startY: Double, endY: Double) {
            self.exerciseNumber = exerciseNumber
            self.type = type
            self.fullContent = fullContent
            self.startY = startY
            self.endY = endY
        }

        enum CodingKeys: String, CodingKey {
            case exerciseNumber, type, fullContent, startY, endY
        }
    }

    /// Analysis result containing lessons and exercises
    struct AnalysisResult: Codable {
        let lessons: [Lesson]
        let exercises: [Exercise]
    }

    /// Result from analyzing a single segment
    private struct SegmentAnalysisResult: Codable {
        let type: String // "lesson", "exercise", or "neither"
        let lesson: Lesson?
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
            var allLessons: [Lesson] = []
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
Classify the TEXT SEGMENT below as exercise, lesson, or neither. Return ONLY JSON, no explanations.

RULES:
- Numbered items (1., 2., a., etc.) = EXERCISE
- Questions or imperatives (Find, Solve, Calculate, Write, Complete) = EXERCISE
- Theoretical explanations = LESSON
- Pure headers/footers only = NEITHER

RESPONSE FORMAT (choose one):
Exercise: {"type":"exercise","exercise":{"exerciseNumber":"NUM","type":"TYPE","fullContent":"TEXT","startY":\(segment.startY),"endY":\(segment.endY)}}
Lesson: {"type":"lesson","lesson":{"topic":"TOPIC","fullContent":"TEXT","startY":\(segment.startY),"endY":\(segment.endY)}}
Neither: {"type":"neither"}

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

                    if segmentResult.type == "lesson", let lesson = segmentResult.lesson {
                        print("DEBUG: Found lesson - \(lesson.topic), Y: \(lesson.startY)-\(lesson.endY)")
                        allLessons.append(lesson)
                    } else if segmentResult.type == "exercise", let exercise = segmentResult.exercise {
                        print("DEBUG: Found exercise #\(exercise.exerciseNumber), Y: \(exercise.startY)-\(exercise.endY)")
                        allExercises.append(exercise)
                    } else {
                        print("DEBUG: Segment classified as 'neither' or no data")
                    }
                } catch {
                    print("DEBUG: Error analyzing segment \(index + 1): \(error.localizedDescription)")
                    print("DEBUG: Continuing with remaining segments...")
                    continue
                }
            }

            // Step 3: Combine all results, sorted by Y-position (document order: top to bottom)
            // In Vision coordinates, higher Y = higher on page, so sort DESCENDING for reading order
            let sortedLessons = allLessons.sorted { $0.startY > $1.startY }
            let sortedExercises = allExercises.sorted { $0.startY > $1.startY }

            print("DEBUG: Final analysis complete - Lessons: \(allLessons.count), Exercises: \(allExercises.count)")
            print("DEBUG: Exercise order after sorting (top to bottom):")
            for (idx, ex) in sortedExercises.enumerated() {
                print("  Position \(idx): Exercise #\(ex.exerciseNumber), Y: \(ex.startY)-\(ex.endY)")
            }

            let finalResult = AnalysisResult(
                lessons: sortedLessons,
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
        You are an educational content analyzer specializing in homework page segmentation. Analyze the provided homework page to identify and categorize ALL content as either lesson/course material or exercises.

        IMPORTANT: Return ONLY valid JSON. Do not include any explanatory text before or after the JSON. Your entire response must be parseable JSON.

        Input Data:
        - Image: A homework page containing lessons and/or exercises
        - OCR text blocks with Y coordinates: "\(ocrBlocksList)"

        Core Classification Rules:

        IMPORTANT HINT: If the text contains ANY questions, question marks, or asks the student to perform a task, it is almost ALWAYS an exercise, NOT a lesson.

        LESSON (theoretical content only):
        - Explanatory text, definitions, formulas, theorems, concepts
        - Worked examples WITH complete solutions already shown
        - Educational text that TEACHES (does NOT ask questions or request action)
        - Must be purely informational/instructional content
        - NO question marks or imperatives

        EXERCISE (tasks for students):
        - Questions, problems, or tasks that ASK the student to do something
        - Must have BOTH identifier (number/letter) AND task body
        - Problems WITHOUT solutions (blank spaces for student responses)
        - Contains question words: "Find", "Calculate", "Solve", "Show", "Prove", "Determine"
        - Contains instruction words: "Complete", "Fill in", "Draw", "Explain"
        - Contains question marks (?) or imperative verbs
        - If it asks a question or requests an action → it's an EXERCISE, not a lesson
        - A heading alone (e.g., "Exercise 1" with no task) is NOT an exercise
        - When the text is more than one paragraph, separate the exercises

        CRITICAL: For each identified content item, determine both START and END positions:
        - startY: Y coordinate where the content begins (from the first relevant OCR block)
        - endY: Y coordinate where the content ends (from the last relevant OCR block)

        Use the OCR block Y coordinates to precisely determine where each lesson or exercise starts and ends. Look for:
        - Natural content boundaries (blank lines, new headings, different formatting)
        - Sequential exercise numbering to determine where one exercise ends and another begins
        - Topic changes that indicate lesson boundaries

        Return a JSON object with this exact structure:
        {
            "lessons": [
                {
                    "topic": "Brief topic description",
                    "fullContent": "Your cleaned-up and properly formatted understanding of the lesson content, with corrected OCR errors and proper mathematical notation",
                    "startY": 0.123,
                    "endY": 0.245
                }
            ],
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
                        lessons: analysisResult.lessons.sorted { $0.startY > $1.startY },
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
        You are an educational exercise generator. Generate \(count) similar practice exercises based on the following exercise.

        Original Exercise:
        Type: \(exercise.type)
        Content: \(exercise.fullContent)

        Generate \(count) similar exercises with varying difficulty levels (same, easier, harder).

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
                "content": "The exercise text here",
                "difficulty": "same"
            },
            {
                "exerciseNumber": "2",
                "type": "\(exercise.type)",
                "content": "The exercise text here",
                "difficulty": "easier"
            },
            {
                "exerciseNumber": "3",
                "type": "\(exercise.type)",
                "content": "The exercise text here",
                "difficulty": "harder"
            }
        ]

        Guidelines:
        - Keep the same exercise type and educational level
        - Vary the numbers, variables, or context but maintain the same concept
        - "same" difficulty: Similar complexity to original
        - "easier": Simpler numbers or fewer steps
        - "harder": More complex numbers or additional steps
        - Ensure exercises are educational and appropriate for students
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

    /// Generates a concise summary of the homework analysis
    ///
    /// - Parameters:
    ///   - analysisResult: The analysis result containing lessons and exercises
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
        let lessonsDesc = analysisResult.lessons.map { "- \($0.topic)" }.joined(separator: "\n")
        let exercisesDesc = analysisResult.exercises.map { "- Exercise \($0.exerciseNumber): \($0.type)" }.joined(separator: "\n")

        let prompt = """
INSTRUCTIONS:
Generate a brief, student-friendly summary (2-3 sentences) of this homework page.

CONTENT FOUND:
Lessons (\(analysisResult.lessons.count)):
\(lessonsDesc.isEmpty ? "None" : lessonsDesc)

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

        // Try to find JSON array boundaries first
        if let startIndex = text.firstIndex(of: "["),
           let endIndex = text.lastIndex(of: "]") {
            let jsonRange = startIndex...endIndex
            jsonString = String(text[jsonRange])
        }
        // Try to find JSON object boundaries
        else if let startIndex = text.firstIndex(of: "{"),
                let endIndex = text.lastIndex(of: "}") {
            let jsonRange = startIndex...endIndex
            jsonString = String(text[jsonRange])
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
