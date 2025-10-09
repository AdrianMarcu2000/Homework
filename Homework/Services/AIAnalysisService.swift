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
    }

    /// Analysis result containing lessons and exercises
    struct AnalysisResult: Codable {
        let lessons: [Lesson]
        let exercises: [Exercise]
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

    /// Analyzes a homework image to identify lessons and exercises
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

        LESSON: Theoretical content OR solved examples
        - Explanatory text, definitions, formulas, concepts
        - Worked examples WITH complete solutions shown
        - Any exercise that already has answers filled in

        EXERCISE: Tasks requiring student action
        - Must have BOTH identifier (number/letter) AND task body
        - Problems WITHOUT solutions
        - Blank spaces or areas for student responses
        - A heading alone (e.g., "Exercise 1" with no task) is NOT an exercise

        Detection Patterns:
        - Numbering: 1., 2), a), (i), A., etc.
        - Question words: "Find", "Calculate", "Solve", "Determine", "Prove"
        - Instruction words: "Show", "Explain", "Draw", "Complete"
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
                    "fullContent": "Complete lesson text",
                    "startY": 0.123,
                    "endY": 0.245
                }
            ],
            "exercises": [
                {
                    "exerciseNumber": "1",
                    "type": "mathematical",
                    "fullContent": "Complete exercise text",
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
        - Include ALL relevant text in fullContent
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
                    let analysisResult = try decoder.decode(AnalysisResult.self, from: data)
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

                print("=== SIMILAR EXERCISES ===")
                print("Full AI Response:")
                print(response.content)
                print("========================")

                let jsonString = extractJSON(from: response.content)

                print("Extracted JSON:")
                print(jsonString)
                print("========================")

                guard let data = jsonString.data(using: .utf8) else {
                    print("ERROR: Failed to convert JSON string to data")
                    print("========================")
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                let exercises = try decoder.decode([SimilarExercise].self, from: data)

                print("SUCCESS: Parsed \(exercises.count) similar exercises")
                print("========================")

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

                print("=== HINTS GENERATION ===")
                print("Full AI Response:")
                print(response.content)
                print("========================")

                let jsonString = extractJSON(from: response.content)

                print("Extracted JSON:")
                print(jsonString)
                print("========================")

                guard let data = jsonString.data(using: .utf8) else {
                    print("ERROR: Failed to convert JSON string to data")
                    print("========================")
                    await MainActor.run {
                        completion(.failure(AIAnalysisError.parsingFailed(NSError(domain: "AIAnalysis", code: -1))))
                    }
                    return
                }

                let decoder = JSONDecoder()
                let hints = try decoder.decode([Hint].self, from: data)

                print("SUCCESS: Parsed \(hints.count) hints")
                print("========================")

                await MainActor.run {
                    completion(.success(hints))
                }
            } catch {
                print("ERROR: Parsing hints failed")
                print("Error details: \(error)")
                print("========================")
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
