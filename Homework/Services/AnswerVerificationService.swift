//
//  AnswerVerificationService.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import UIKit
import Foundation
import FirebaseAppCheck
import PencilKit

/// Result of answer verification from cloud
struct VerificationResult: Codable, Sendable {
    let isCorrect: Bool
    let confidence: String // "high", "medium", "low"
    let feedback: String
    let suggestions: String?
}

/// Request structure for answer verification
struct VerificationRequest: Sendable {
    let exerciseContent: String
    let exerciseSubject: String?
    let answerType: String // "canvas", "text", "inline"
    let answerText: String?
    let answerImageBase64: String?
    let answerImageMimeType: String?
}

// Explicitly implement Encodable
extension VerificationRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case exerciseContent, exerciseSubject, answerType, answerText, answerImageBase64, answerImageMimeType
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseContent, forKey: .exerciseContent)
        try container.encodeIfPresent(exerciseSubject, forKey: .exerciseSubject)
        try container.encode(answerType, forKey: .answerType)
        try container.encodeIfPresent(answerText, forKey: .answerText)
        try container.encodeIfPresent(answerImageBase64, forKey: .answerImageBase64)
        try container.encodeIfPresent(answerImageMimeType, forKey: .answerImageMimeType)
    }
}

/// Service for verifying homework answers using cloud AI
class AnswerVerificationService {
    static let shared = AnswerVerificationService()

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

    /// Verifies an answer for a homework exercise
    ///
    /// - Parameters:
    ///   - exercise: The exercise being answered
    ///   - answerType: Type of answer (canvas, text, inline)
    ///   - answerText: Text answer (for text/inline types)
    ///   - canvasDrawing: PencilKit drawing (for canvas type)
    ///   - completion: Callback with verification result or error
    func verifyAnswer(
        exercise: AIAnalysisService.Exercise,
        answerType: String,
        answerText: String? = nil,
        canvasDrawing: PKDrawing? = nil,
        completion: @escaping (Result<VerificationResult, Error>) -> Void
    ) {
        #if DEBUG
        let appCheckToken = "emulator-bypass-token"
        print("🔐 DEBUG VERIFY: Using emulator bypass token")

        performVerificationRequest(
            exercise: exercise,
            answerType: answerType,
            answerText: answerText,
            canvasDrawing: canvasDrawing,
            appCheckToken: appCheckToken,
            completion: completion
        )
        #else
        print("🔐 RELEASE: Getting App Check token for verification...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                print("❌ App Check token error - \(error.localizedDescription)")
                completion(.failure(VerificationError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                print("❌ No App Check token received")
                completion(.failure(VerificationError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            print("✅ App Check token obtained for verification")

            self.performVerificationRequest(
                exercise: exercise,
                answerType: answerType,
                answerText: answerText,
                canvasDrawing: canvasDrawing,
                appCheckToken: appCheckToken,
                completion: completion
            )
        }
        #endif
    }

    /// Performs the actual verification request
    private func performVerificationRequest(
        exercise: AIAnalysisService.Exercise,
        answerType: String,
        answerText: String?,
        canvasDrawing: PKDrawing?,
        appCheckToken: String,
        completion: @escaping (Result<VerificationResult, Error>) -> Void
    ) {
        // Prepare the request body
        var answerImageBase64: String?
        var answerImageMimeType: String?

        // If canvas type, convert drawing to image
        if answerType == "canvas", let drawing = canvasDrawing {
            let image = drawing.image(from: drawing.bounds, scale: 2.0)
            if let imageData = image.jpegData(compressionQuality: 0.7) {
                answerImageBase64 = imageData.base64EncodedString()
                answerImageMimeType = "image/jpeg"
                print("DEBUG VERIFY: Converted canvas to image - \(imageData.count) bytes")
            }
        }

        // Create request body
        let requestBody = VerificationRequest(
            exerciseContent: exercise.fullContent,
            exerciseSubject: exercise.subject,
            answerType: answerType,
            answerText: answerText,
            answerImageBase64: answerImageBase64,
            answerImageMimeType: answerImageMimeType
        )

        // Create URL request
        let url = URL(string: "\(Config.baseURL)/verifyAnswer")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(VerificationError.encodingFailed(error)))
            return
        }

        print("DEBUG VERIFY: Sending verification request for exercise \(exercise.exerciseNumber)")
        print("DEBUG VERIFY: Answer type: \(answerType)")

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DEBUG VERIFY: Network error - \(error.localizedDescription)")
                completion(.failure(VerificationError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(VerificationError.invalidResponse))
                return
            }

            print("DEBUG VERIFY: Response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                print("DEBUG VERIFY: Error response: \(errorMessage)")
                completion(.failure(VerificationError.serverError(httpResponse.statusCode, errorMessage)))
                return
            }

            guard let data = data else {
                completion(.failure(VerificationError.noData))
                return
            }

            // Decode verification result
            do {
                let result = try JSONDecoder().decode(VerificationResult.self, from: data)
                print("DEBUG VERIFY: Verification complete - Correct: \(result.isCorrect), Confidence: \(result.confidence)")
                completion(.success(result))
            } catch {
                print("DEBUG VERIFY: Decoding error - \(error.localizedDescription)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("DEBUG VERIFY: Raw response: \(jsonString)")
                }
                completion(.failure(VerificationError.decodingFailed(error)))
            }
        }

        task.resume()
    }

    /// Errors that can occur during verification
    enum VerificationError: LocalizedError {
        case encodingFailed(Error)
        case networkError(Error)
        case invalidResponse
        case serverError(Int, String)
        case noData
        case decodingFailed(Error)
        case appCheckFailed(Error)
        case noAppCheckToken
        case noAnswer

        var errorDescription: String? {
            switch self {
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
            case .noAnswer:
                return "No answer provided to verify"
            }
        }
    }
}
