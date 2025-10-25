//
//  AgenticCloudAnalysisService.swift
//  Homework
//
//  Service for analyzing homework using multi-agent cloud analysis
//  This service wraps the agentic Firebase Functions endpoint
//

import UIKit
import Foundation
import FirebaseAppCheck
import OSLog

/// Service for analyzing homework using cloud-based multi-agent LLMs via Firebase Functions
class AgenticCloudAnalysisService {
    static let shared = AgenticCloudAnalysisService()

    private init() {}

    /// Configuration (uses centralized FirebaseConfig)
    private struct Config {
        static let requestTimeout = FirebaseConfig.Timeouts.agenticRequest
        static let resourceTimeout = FirebaseConfig.Timeouts.agenticResource
        static let maxRetries = FirebaseConfig.Retry.maxRetries
        static let retryDelay = FirebaseConfig.Retry.delaySeconds
    }

    /// Custom URLSession with extended timeouts for cloud functions
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.requestTimeout
        config.timeoutIntervalForResource = Config.resourceTimeout
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Analyzes homework using agentic cloud analysis
    ///
    /// - Parameters:
    ///   - image: The homework page image
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates
    ///   - userPreferences: Optional user preferences for analysis
    ///   - completion: Callback with the agentic analysis result or error
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        userPreferences: AgenticAnalysisRequest.UserPreferences? = nil,
        completion: @escaping (Result<AgenticAnalysisResponse, Error>) -> Void
    ) {
        #if DEBUG
        // In DEBUG mode, skip App Check for local emulator testing
        let appCheckToken = "emulator-bypass-token"
        AppLogger.cloud.info("DEBUG mode: Using emulator bypass token for agentic analysis")

        // Proceed directly to analysis
        self.performAgenticAnalysisRequest(
            image: image,
            ocrBlocks: ocrBlocks,
            userPreferences: userPreferences,
            appCheckToken: appCheckToken,
            completion: completion
        )
        #else
        // In RELEASE mode, get real App Check token
        AppLogger.cloud.info("RELEASE mode: Getting App Check token for agentic analysis...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.cloud.error("App Check token error for agentic analysis", error: error)
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.cloud.error("No App Check token received for agentic analysis")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.cloud.info("App Check token obtained for agentic analysis")

            // Proceed with the request
            self.performAgenticAnalysisRequest(
                image: image,
                ocrBlocks: ocrBlocks,
                userPreferences: userPreferences,
                appCheckToken: appCheckToken,
                completion: completion
            )
        }
        #endif
    }

    /// Async version of analyzeHomework
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        userPreferences: AgenticAnalysisRequest.UserPreferences? = nil
    ) async -> Result<AgenticAnalysisResponse, Error> {
        return await withCheckedContinuation { continuation in
            analyzeHomework(image: image, ocrBlocks: ocrBlocks, userPreferences: userPreferences) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Performs the actual agentic analysis request with the given App Check token
    private func performAgenticAnalysisRequest(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        userPreferences: AgenticAnalysisRequest.UserPreferences?,
        appCheckToken: String,
        completion: @escaping (Result<AgenticAnalysisResponse, Error>) -> Void,
        retryCount: Int = 0
    ) {
        // Step 1: Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            completion(.failure(CloudAnalysisError.imageConversionFailed))
            return
        }
        let imageBase64 = imageData.base64EncodedString()

        // Step 2: Convert OCR blocks to request format
        let ocrBlocksData = ocrBlocks.map { block in
            AgenticAnalysisRequest.OCRBlockData(
                text: block.text,
                startY: block.startY,
                endY: block.endY
            )
        }

        AppLogger.cloud.info("📤 SENDING AGENTIC ANALYSIS REQUEST TO CLOUD:")
        AppLogger.cloud.info("Number of OCR blocks: \(ocrBlocks.count)")
        AppLogger.cloud.info("User preferences: \(userPreferences != nil ? "Yes" : "No")")

        // Step 3: Create request
        let requestBody = AgenticAnalysisRequest(
            imageBase64: imageBase64,
            ocrBlocks: ocrBlocksData,
            userPreferences: userPreferences
        )

        // Step 4: Call Firebase endpoint with App Check token
        let url = FirebaseConfig.Endpoint.analyzeHomeworkAgentic.url
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

        AppLogger.cloud.info("Sending agentic analysis request to \(url.absoluteString)")
        AppLogger.cloud.debug("Request size: \(request.httpBody?.count ?? 0) bytes")
        AppLogger.cloud.debug("Timeout: request=\(Config.requestTimeout)s, resource=\(Config.resourceTimeout)s")
        if retryCount > 0 {
            AppLogger.cloud.info("Retry attempt \(retryCount) of \(Config.maxRetries)")
        }

        // Step 5: Execute request with custom session
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                AppLogger.cloud.error("Network error in agentic analysis", error: error)
                AppLogger.cloud.debug("Error domain: \(nsError.domain), code: \(nsError.code)")

                // Check if it's a timeout or connection error that can be retried
                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performAgenticAnalysisRequest(
                            image: image,
                            ocrBlocks: ocrBlocks,
                            userPreferences: userPreferences,
                            appCheckToken: appCheckToken,
                            completion: completion,
                            retryCount: retryCount + 1
                        )
                    }
                    return
                }

                completion(.failure(CloudAnalysisError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(CloudAnalysisError.invalidResponse))
                return
            }

            AppLogger.cloud.debug("Agentic analysis response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Server returned error: \(errorMessage)")

                // Retry on 500-level errors (server issues)
                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performAgenticAnalysisRequest(
                            image: image,
                            ocrBlocks: ocrBlocks,
                            userPreferences: userPreferences,
                            appCheckToken: appCheckToken,
                            completion: completion,
                            retryCount: retryCount + 1
                        )
                    }
                    return
                }

                completion(.failure(CloudAnalysisError.serverError(httpResponse.statusCode, errorMessage)))
                return
            }

            guard let data = data else {
                completion(.failure(CloudAnalysisError.noData))
                return
            }

            // Log the raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                AppLogger.cloud.info("📥 RECEIVED AGENTIC ANALYSIS RESPONSE FROM CLOUD:")
                AppLogger.cloud.info("Response length: \(data.count) bytes")
                AppLogger.cloud.info("---RESPONSE START---")
                AppLogger.cloud.info(jsonString)
                AppLogger.cloud.info("---RESPONSE END---")
            }

            // Decode agentic response on a detached task to avoid actor isolation issues
            Task.detached {
                do {
                    let decoder = JSONDecoder()
                    let agenticResponse = try decoder.decode(AgenticAnalysisResponse.self, from: data)

                    await MainActor.run {
                        AppLogger.cloud.info("✅ Successfully decoded agentic response")
                        AppLogger.cloud.info("Subject: \(agenticResponse.routing.subject)")
                        AppLogger.cloud.info("Content Type: \(agenticResponse.routing.contentType)")
                        AppLogger.cloud.info("Agent Used: \(agenticResponse.routing.agentUsed)")
                        AppLogger.cloud.info("Confidence: \(String(format: "%.2f", agenticResponse.routing.confidence))")
                        AppLogger.cloud.info("Processing Time: \(agenticResponse.metadata.processingTimeMs)ms")

                        if let exercises = agenticResponse.analysis.exercises {
                            AppLogger.cloud.info("Exercises Found: \(exercises.count)")
                        }
                        if agenticResponse.analysis.summary != nil {
                            AppLogger.cloud.info("Study Material Summary: Yes")
                        }
                    }

                    completion(.success(agenticResponse))
                } catch {
                    await MainActor.run {
                        AppLogger.cloud.error("❌ Agentic response decoding failed", error: error)
                        if let jsonString = String(data: data, encoding: .utf8) {
                            AppLogger.cloud.error("Raw response causing error: \(jsonString.prefix(500))...")
                        }
                    }
                    completion(.failure(CloudAnalysisError.decodingFailed(error)))
                }
            }
        }

        task.resume()
    }

    /// Converts agentic response to legacy AnalysisResult for backward compatibility
    ///
    /// - Parameter agenticResponse: The agentic analysis response
    /// - Returns: Converted AnalysisResult that works with existing UI
    func convertToAnalysisResult(_ agenticResponse: AgenticAnalysisResponse) -> AnalysisResult {
        return agenticResponse.toAnalysisResult()
    }
}

// MARK: - OCRBlock Extension

extension OCRBlock {
    /// Computed property for backward compatibility
    var startY: Double {
        return self.y // Assuming y is the start position
    }

    /// Computed property for end position (approximation)
    var endY: Double {
        return self.y + 0.05 // Approximate 5% height for each block
    }
}
