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
import OSLog

/// Result of answer verification from cloud
struct VerificationResult: Sendable {
    let isCorrect: Bool
    let confidence: String // "high", "medium", "low"
    let feedback: String
    let suggestions: String?
}

// Explicitly implement Codable outside of MainActor context
extension VerificationResult: Codable {
    enum CodingKeys: String, CodingKey {
        case isCorrect, confidence, feedback, suggestions
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isCorrect = try container.decode(Bool.self, forKey: .isCorrect)
        self.confidence = try container.decode(String.self, forKey: .confidence)
        self.feedback = try container.decode(String.self, forKey: .feedback)
        self.suggestions = try container.decodeIfPresent(String.self, forKey: .suggestions)
    }
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
            return "http://127.0.0.1:5001/homework-daef1/us-central1"
            #else
            return "https://us-central1-homework-daef1.cloudfunctions.net"
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
        AppLogger.persistence.info("DEBUG mode: Using emulator bypass token for verification")

        performVerificationRequest(
            exercise: exercise,
            answerType: answerType,
            answerText: answerText,
            canvasDrawing: canvasDrawing,
            appCheckToken: appCheckToken,
            completion: completion
        )
        #else
        AppLogger.persistence.info("RELEASE mode: Getting App Check token for verification...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.persistence.error("App Check token error", error: error)
                completion(.failure(VerificationError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.persistence.error("No App Check token received")
                completion(.failure(VerificationError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.persistence.info("App Check token obtained for verification")

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

        AppLogger.persistence.info("Verifying \(answerType) answer for exercise \(exercise.exerciseNumber)")

        // Execute request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                AppLogger.persistence.error("Network error in verification", error: error)
                completion(.failure(VerificationError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(VerificationError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.persistence.error("Verification error response: \(errorMessage)")
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
                AppLogger.persistence.info("Verification complete - Correct: \(result.isCorrect), Confidence: \(result.confidence)")
                completion(.success(result))
            } catch {
                AppLogger.persistence.error("Verification decoding error", error: error)
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
