//
//  CloudAnalysisService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import UIKit
import Foundation
import FirebaseAppCheck

/// Cloud response structure matching Firebase function output
struct CloudAnalysisResult: Sendable {
    let summary: String
    let sections: [Section]

    struct Section: Sendable {
        let type: String // "EXERCISE" or "SKIP"
        let title: String
        let content: String
        let subject: String?
        let inputType: String?
        let yStart: Int
        let yEnd: Int
    }
}

// Explicitly implement Codable outside of MainActor context
extension CloudAnalysisResult: Codable {
    enum CodingKeys: String, CodingKey {
        case summary, sections
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.sections = try container.decode([Section].self, forKey: .sections)
    }
}

extension CloudAnalysisResult.Section: Codable {
    enum CodingKeys: String, CodingKey {
        case type, title, content, subject, inputType, yStart, yEnd
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject)
        self.inputType = try container.decodeIfPresent(String.self, forKey: .inputType)
        self.yStart = try container.decode(Int.self, forKey: .yStart)
        self.yEnd = try container.decode(Int.self, forKey: .yEnd)
    }
}

/// Request structure for cloud analysis
struct AnalysisRequest: Sendable {
    let imageBase64: String
    let imageMimeType: String
    let ocrJsonText: String
}

// Explicitly implement Encodable outside of MainActor context
extension AnalysisRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case imageBase64, imageMimeType, ocrJsonText
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageBase64, forKey: .imageBase64)
        try container.encode(imageMimeType, forKey: .imageMimeType)
        try container.encode(ocrJsonText, forKey: .ocrJsonText)
    }
}

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
        #if DEBUG
        // In DEBUG mode, skip App Check for local emulator testing
        // Use a bypass token that the emulator will accept
        let appCheckToken = "emulator-bypass-token"
        print("🔐 DEBUG CLOUD: Using emulator bypass token (App Check disabled)")
        print("💡 To test App Check, build in RELEASE mode on a physical device")

        // Proceed directly to image conversion
        self.performAnalysisRequest(
            image: image,
            ocrBlocks: ocrBlocks,
            appCheckToken: appCheckToken,
            completion: completion
        )
        #else
        // In RELEASE mode, get real App Check token
        print("🔐 RELEASE: Getting App Check token...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                print("❌ App Check token error - \(error.localizedDescription)")
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                print("❌ No App Check token received")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            print("✅ App Check token obtained successfully")

            // Proceed with the request
            self.performAnalysisRequest(
                image: image,
                ocrBlocks: ocrBlocks,
                appCheckToken: appCheckToken,
                completion: completion
            )
        }
        #endif
    }

    /// Performs the actual analysis request with the given App Check token
    private func performAnalysisRequest(
        image: UIImage,
        ocrBlocks: [AIAnalysisService.OCRBlock],
        appCheckToken: String,
        completion: @escaping (Result<AIAnalysisService.AnalysisResult, Error>) -> Void
    ) {
        // Step 1: Convert image to base64
        // Compress more aggressively for faster upload/processing
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            completion(.failure(CloudAnalysisError.imageConversionFailed))
            return
        }
        let imageBase64 = imageData.base64EncodedString()

        // Step 2: Format OCR blocks as text with coordinates
        let ocrJsonText = self.formatOCRBlocks(ocrBlocks)

        // Step 3: Create request
        let requestBody = AnalysisRequest(
            imageBase64: imageBase64,
            imageMimeType: "image/jpeg",
            ocrJsonText: ocrJsonText
        )

        // Step 4: Call Firebase endpoint with App Check token
        let url = URL(string: "\(Config.baseURL)/analyzeHomework")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(CloudAnalysisError.encodingFailed(error)))
            return
        }

        print("DEBUG CLOUD: Sending request to \(url.absoluteString)")
        print("DEBUG CLOUD: OCR text length: \(ocrJsonText.count) characters")

        // Step 5: Execute request
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

            // Decode and convert
            do {
                let cloudResult = try JSONDecoder().decode(CloudAnalysisResult.self, from: data)
                print("DEBUG CLOUD: Successfully decoded response - Summary: \(cloudResult.summary)")
                print("DEBUG CLOUD: Found \(cloudResult.sections.count) sections")

                // Convert to our format
                let analysisResult = Self.convertToAnalysisResult(cloudResult)
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
    private static func convertToAnalysisResult(_ cloudResult: CloudAnalysisResult) -> AIAnalysisService.AnalysisResult {
        var exercises: [AIAnalysisService.Exercise] = []

        print("DEBUG CLOUD: Converting cloud result to exercises...")
        print("DEBUG CLOUD: Total sections: \(cloudResult.sections.count)")

        for (_, section) in cloudResult.sections.enumerated() {
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
                    endY: endY,
                    subject: section.subject,
                    inputType: section.inputType
                )
                exercises.append(exercise)

                // Log exercise details with corrected content
                let subjectStr = section.subject ?? "N/A"
                let inputTypeStr = section.inputType ?? "N/A"
                print("📝 Exercise #\(exerciseNumber): Subject=\(subjectStr), Input=\(inputTypeStr), Type=\(exercise.type)")
                print("   ✅ CORRECTED CONTENT (from LLM): \(section.content.prefix(100))...")
                if section.content.count > 100 {
                    print("      (content length: \(section.content.count) chars)")
                }
            } else {
                print("DEBUG CLOUD: Skipping section type: \(section.type)")
            }
        }

        // Sort by Y position (descending for top-to-bottom order)
        let sortedExercises = exercises.sorted { $0.startY > $1.startY }
        print("DEBUG CLOUD: ✅ Successfully converted to \(sortedExercises.count) exercises")

        return AIAnalysisService.AnalysisResult(exercises: sortedExercises)
    }

    /// Extracts exercise number from title
    private static func extractExerciseNumber(from title: String) -> String {
        // Look for digits in the title
        let digits = title.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return digits.isEmpty ? "1" : digits
    }

    /// Infers exercise type from content
    private static func inferExerciseType(from content: String) -> String {
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
        case appCheckFailed(Error)
        case noAppCheckToken

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
            case .appCheckFailed(let error):
                return "App Check verification failed: \(error.localizedDescription)"
            case .noAppCheckToken:
                return "Failed to obtain App Check token"
            }
        }
    }
}
