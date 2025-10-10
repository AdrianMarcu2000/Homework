//
//  CloudAnalysisService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import UIKit
import Foundation

/// Service for analyzing homework using cloud-based LLMs via Firebase Functions
class CloudAnalysisService {
    static let shared = CloudAnalysisService()

    private init() {}

    /// Configuration for Firebase endpoint
    struct Config {
        static var baseURL: String {
            #if DEBUG
            return "http://127.0.0.1:5001/homework-66038/us-central1"
            #else
            return "https://us-central1-homework-66038.cloudfunctions.net"
            #endif
        }
    }

    /// Request structure for cloud analysis
    private struct AnalysisRequest: Encodable {
        let imageBase64: String
        let imageMimeType: String
        let ocrJsonText: String
    }

    /// Cloud response structure matching Firebase function output
    struct CloudAnalysisResult: Codable {
        let summary: String
        let sections: [Section]

        struct Section: Codable {
            let type: String // "EXERCISE" or "SKIP"
            let title: String
            let content: String
            let yStart: Int
            let yEnd: Int
        }
    }

    /// Analyzes homework using cloud LLM
    ///
    /// - Parameters:
    ///   - image: The homework page image
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates
    ///   - completion: Callback with the analysis result or error
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [AIAnalysisService.OCRBlock],
        completion: @escaping (Result<AIAnalysisService.AnalysisResult, Error>) -> Void
    ) {
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(CloudAnalysisError.imageConversionFailed))
            return
        }
        let imageBase64 = imageData.base64EncodedString()

        // Format OCR blocks as text with coordinates
        let ocrJsonText = formatOCRBlocks(ocrBlocks)

        // Create request
        let requestBody = AnalysisRequest(
            imageBase64: imageBase64,
            imageMimeType: "image/jpeg",
            ocrJsonText: ocrJsonText
        )

        // Call Firebase endpoint
        let url = URL(string: "\(Config.baseURL)/analyzeHomework")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(CloudAnalysisError.encodingFailed(error)))
            return
        }

        print("DEBUG CLOUD: Sending request to \(url.absoluteString)")
        print("DEBUG CLOUD: OCR text length: \(ocrJsonText.count) characters")

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG CLOUD: Network error - \(error.localizedDescription)")
                completion(.failure(CloudAnalysisError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(CloudAnalysisError.invalidResponse))
                return
            }

            print("DEBUG CLOUD: Response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                print("DEBUG CLOUD: Error response: \(errorMessage)")
                completion(.failure(CloudAnalysisError.serverError(httpResponse.statusCode, errorMessage)))
                return
            }

            guard let data = data else {
                completion(.failure(CloudAnalysisError.noData))
                return
            }

            do {
                // Parse cloud response
                let cloudResult = try JSONDecoder().decode(CloudAnalysisResult.self, from: data)
                print("DEBUG CLOUD: Successfully decoded response - Summary: \(cloudResult.summary)")
                print("DEBUG CLOUD: Found \(cloudResult.sections.count) sections")

                // Convert to our format
                let analysisResult = self.convertToAnalysisResult(cloudResult)
                print("DEBUG CLOUD: Converted to - Exercises: \(analysisResult.exercises.count)")

                completion(.success(analysisResult))
            } catch {
                print("DEBUG CLOUD: Decoding error - \(error.localizedDescription)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("DEBUG CLOUD: Raw response: \(jsonString)")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }

    /// Formats OCR blocks into text format for the cloud API
    private func formatOCRBlocks(_ blocks: [AIAnalysisService.OCRBlock]) -> String {
        var result = "OCR Text Analysis with Y-coordinates:\n\n"

        for (index, block) in blocks.enumerated() {
            let yCoord = Int(block.y * 1000) // Convert normalized to integer
            result += "Block \(index + 1) (Y: \(yCoord)): \(block.text)\n"
        }

        return result
    }

    /// Converts cloud response to our internal format
    private func convertToAnalysisResult(_ cloudResult: CloudAnalysisResult) -> AIAnalysisService.AnalysisResult {
        var exercises: [AIAnalysisService.Exercise] = []

        for section in cloudResult.sections {
            // Normalize Y coordinates back to 0-1 range
            let startY = Double(section.yStart) / 1000.0
            let endY = Double(section.yEnd) / 1000.0

            if section.type == "EXERCISE" {
                // Extract exercise number from title (e.g., "Exercise 8" -> "8")
                let exerciseNumber = extractExerciseNumber(from: section.title)
                let exercise = AIAnalysisService.Exercise(
                    exerciseNumber: exerciseNumber,
                    type: inferExerciseType(from: section.content),
                    fullContent: section.content,
                    startY: startY,
                    endY: endY
                )
                exercises.append(exercise)
                print("DEBUG CLOUD: Converted exercise #\(exerciseNumber)")
            } else {
                print("DEBUG CLOUD: Skipping section type: \(section.type)")
            }
        }

        // Sort by Y position (descending for top-to-bottom order)
        return AIAnalysisService.AnalysisResult(
            exercises: exercises.sorted { $0.startY > $1.startY }
        )
    }

    /// Extracts exercise number from title
    private func extractExerciseNumber(from title: String) -> String {
        // Look for digits in the title
        let digits = title.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return digits.isEmpty ? "1" : digits
    }

    /// Infers exercise type from content
    private func inferExerciseType(from content: String) -> String {
        let lowercased = content.lowercased()

        if lowercased.contains("multiple choice") || lowercased.contains("choose") {
            return "multiple_choice"
        } else if lowercased.contains("true") && lowercased.contains("false") {
            return "true_or_false"
        } else if lowercased.contains("fill in") || lowercased.contains("complete") {
            return "fill_in_blanks"
        } else if lowercased.contains("draw") || lowercased.contains("diagram") {
            return "diagram"
        } else if lowercased.contains("prove") || lowercased.contains("proof") {
            return "proof"
        } else if lowercased.contains("calculate") || lowercased.contains("compute") {
            return "calculation"
        } else {
            return "mathematical"
        }
    }

    /// Errors that can occur during cloud analysis
    enum CloudAnalysisError: LocalizedError {
        case imageConversionFailed
        case encodingFailed(Error)
        case networkError(Error)
        case invalidResponse
        case serverError(Int, String)
        case noData
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .imageConversionFailed:
                return "Failed to convert image to JPEG format"
            case .encodingFailed(let error):
                return "Failed to encode request: \(error.localizedDescription)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from server"
            case .serverError(let code, let message):
                return "Server error (\(code)): \(message)"
            case .noData:
                return "No data received from server"
            case .decodingFailed(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            }
        }
    }
}
