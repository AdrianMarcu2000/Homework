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

    /// Extracts JSON from a response that might contain additional text
    private func extractJSON(from text: String) -> String {
        // Try to find JSON object boundaries
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            let jsonRange = startIndex...endIndex
            return String(text[jsonRange])
        }

        // If no JSON markers found, return the original text
        return text
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
