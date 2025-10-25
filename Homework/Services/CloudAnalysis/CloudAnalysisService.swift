//
//  CloudAnalysisService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import UIKit
import Foundation
import FirebaseAppCheck
import OSLog

/// Service for analyzing homework using cloud-based LLMs via Firebase Functions
class CloudAnalysisService {
    static let shared = CloudAnalysisService()

    private init() {}

    /// Configuration (uses centralized FirebaseConfig)
    private struct Config {
        static let requestTimeout = FirebaseConfig.Timeouts.standardRequest
        static let resourceTimeout = FirebaseConfig.Timeouts.standardResource
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


    /// Analyzes homework using cloud LLM (single image)
    ///
    /// - Parameters:
    ///   - image: The homework page image
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates
    ///   - completion: Callback with the analysis result or error
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock]
    ) async -> Result<AnalysisResult, Error> {
        return await withCheckedContinuation { continuation in
            analyzeHomework(image: image, ocrBlocks: ocrBlocks) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Analyzes homework using cloud LLM (multiple images)
    ///
    /// - Parameters:
    ///   - images: Array of homework page images
    ///   - ocrBlocks: Array of OCR text blocks with Y coordinates (combined from all pages)
    ///   - completion: Callback with the analysis result or error
    func analyzeHomework(
        images: [UIImage],
        ocrBlocks: [OCRBlock],
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        AppLogger.cloud.info("Multi-image analysis: combining \(images.count) images into single image for cloud analysis")

        // For now, combine multiple images into one and use existing single-image endpoint
        // This is a temporary solution until the multi-image cloud function is deployed
        guard let combinedImage = PDFProcessingService.shared.combineImages(images, spacing: 20) else {
            completion(.failure(CloudAnalysisError.imageConversionFailed))
            return
        }

        // Use the existing single-image analysis method with the combined image
        analyzeHomework(image: combinedImage, ocrBlocks: ocrBlocks, completion: completion)
    }

    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        #if DEBUG
        // In DEBUG mode, skip App Check for local emulator testing
        // Use a bypass token that the emulator will accept
        let appCheckToken = "emulator-bypass-token"
        AppLogger.cloud.info("DEBUG mode: Using emulator bypass token (App Check disabled)")
        AppLogger.cloud.debug("To test App Check, build in RELEASE mode on a physical device")

        // Proceed directly to image conversion
        self.performAnalysisRequest(
            image: image,
            ocrBlocks: ocrBlocks,
            appCheckToken: appCheckToken,
            completion: completion
        )
        #else
        // In RELEASE mode, get real App Check token
        AppLogger.cloud.info("RELEASE mode: Getting App Check token...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.cloud.error("App Check token error", error: error)
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.cloud.error("No App Check token received")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.cloud.info("App Check token obtained successfully")

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

    /// Analyzes text-only homework (no image) using cloud LLM
    ///
    /// - Parameters:
    ///   - text: The homework text to analyze
    ///   - completion: Callback with the analysis result or error
    func analyzeTextOnly(
        text: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void
    ) {
        #if DEBUG
        let appCheckToken = "emulator-bypass-token"
        AppLogger.cloud.info("DEBUG mode: Using emulator bypass token for text-only analysis")
        performTextOnlyAnalysisRequest(text: text, appCheckToken: appCheckToken, completion: completion)
        #else
        AppLogger.cloud.info("RELEASE mode: Getting App Check token for text-only analysis...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.cloud.error("App Check token error for text-only analysis", error: error)
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.cloud.error("No App Check token received for text-only analysis")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.cloud.info("App Check token obtained for text-only analysis")

            self.performTextOnlyAnalysisRequest(text: text, appCheckToken: appCheckToken, completion: completion)
        }
        #endif
    }

    /// Performs the actual analysis request with the given App Check token
    private func performAnalysisRequest(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        appCheckToken: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void,
        retryCount: Int = 0
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

        AppLogger.cloud.info("📤 SENDING ANALYSIS REQUEST TO CLOUD AI:")
        AppLogger.cloud.info("Number of OCR blocks: \(ocrBlocks.count)")
        AppLogger.cloud.info("OCR text length: \(ocrJsonText.count) characters")
        AppLogger.cloud.info("---OCR BLOCKS START---")
        AppLogger.cloud.info(ocrJsonText)
        AppLogger.cloud.info("---OCR BLOCKS END---")

        // Step 3: Create request
        let requestBody = AnalysisRequest(
            imageBase64: imageBase64,
            imageMimeType: "image/jpeg",
            ocrJsonText: ocrJsonText
        )

        // Step 4: Call Firebase endpoint with App Check token
        let url = FirebaseConfig.Endpoint.analyzeHomework.url
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

        AppLogger.cloud.info("Sending analysis request to \(url.absoluteString)")
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
                AppLogger.cloud.error("Network error", error: error)
                AppLogger.cloud.debug("Error domain: \(nsError.domain), code: \(nsError.code)")

                // Check if it's a timeout or connection error that can be retried
                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performAnalysisRequest(
                            image: image,
                            ocrBlocks: ocrBlocks,
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

            AppLogger.cloud.debug("Response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Server returned error: \(errorMessage)")

                // Retry on 500-level errors (server issues)
                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performAnalysisRequest(
                            image: image,
                            ocrBlocks: ocrBlocks,
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
                AppLogger.cloud.info("📥 RECEIVED RESPONSE FROM CLOUD AI:")
                AppLogger.cloud.info("Response length: \(data.count) bytes")
                AppLogger.cloud.info("---RESPONSE START---")
                AppLogger.cloud.info(jsonString)
                AppLogger.cloud.info("---RESPONSE END---")
            }

            // Decode and convert
            do {
                let cloudResult = try JSONDecoder().decode(CloudAnalysisResult.self, from: data)
                AppLogger.cloud.info("✅ Successfully decoded response - Summary: \(cloudResult.summary)")
                AppLogger.cloud.info("Found \(cloudResult.sections.count) sections")

                // Log each section
                for (index, section) in cloudResult.sections.enumerated() {
                    AppLogger.cloud.info("Section \(index + 1): type=\(section.type), title=\(section.title), yStart=\(section.yStart), yEnd=\(section.yEnd)")
                    AppLogger.cloud.info("  Content preview: \(section.content.prefix(100))...")
                }

                // Convert to our format
                let analysisResult = Self.convertToAnalysisResult(cloudResult)
                AppLogger.cloud.info("Converted to \(analysisResult.exercises.count) exercises")

                // Log final exercises
                for (index, exercise) in analysisResult.exercises.enumerated() {
                    AppLogger.cloud.info("Exercise \(index + 1): #\(exercise.exerciseNumber), type=\(exercise.type), subject=\(exercise.subject ?? "N/A"), startY=\(String(format: "%.3f", exercise.startY)), endY=\(String(format: "%.3f", exercise.endY))")
                }

                completion(.success(analysisResult))
            } catch {
                AppLogger.cloud.error("❌ Decoding failed", error: error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLogger.cloud.error("Raw response causing error: \(jsonString.prefix(500))...")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }

    /// Performs text-only analysis request with the given App Check token
    /// Uses the analyzeTextOnly Firebase function endpoint
    private func performTextOnlyAnalysisRequest(
        text: String,
        appCheckToken: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void,
        retryCount: Int = 0
    ) {
        AppLogger.cloud.info("📤 SENDING TEXT-ONLY ANALYSIS REQUEST TO CLOUD AI:")
        AppLogger.cloud.info("Text length: \(text.count) characters")
        AppLogger.cloud.info("---TEXT START---")
        AppLogger.cloud.info(text)
        AppLogger.cloud.info("---TEXT END---")

        // Create request body
        let requestBody: [String: Any] = [
            "text": text
        ]

        // Call Firebase endpoint with App Check token
        let url = FirebaseConfig.Endpoint.analyzeTextOnly.url
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(CloudAnalysisError.encodingFailed(error)))
            return
        }

        AppLogger.cloud.info("Sending text-only analysis request to \(url.absoluteString)")
        AppLogger.cloud.debug("Request size: \(request.httpBody?.count ?? 0) bytes")
        if retryCount > 0 {
            AppLogger.cloud.info("Retry attempt \(retryCount) of \(Config.maxRetries)")
        }

        // Execute request with custom session
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                AppLogger.cloud.error("Network error in text-only analysis", error: error)
                AppLogger.cloud.debug("Error domain: \(nsError.domain), code: \(nsError.code)")

                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performTextOnlyAnalysisRequest(
                            text: text,
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

            AppLogger.cloud.debug("Text-only analysis response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Server returned error: \(errorMessage)")

                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performTextOnlyAnalysisRequest(
                            text: text,
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
                AppLogger.cloud.info("📥 RECEIVED TEXT-ONLY ANALYSIS RESPONSE FROM CLOUD AI:")
                AppLogger.cloud.info("Response length: \(data.count) bytes")
                AppLogger.cloud.info("---RESPONSE START---")
                AppLogger.cloud.info(jsonString)
                AppLogger.cloud.info("---RESPONSE END---")
            }

            // Decode and convert
            do {
                let cloudResult = try JSONDecoder().decode(CloudAnalysisResult.self, from: data)
                AppLogger.cloud.info("✅ Successfully decoded text-only response - Summary: \(cloudResult.summary)")
                AppLogger.cloud.info("Found \(cloudResult.sections.count) sections")

                // Log each section
                for (index, section) in cloudResult.sections.enumerated() {
                    AppLogger.cloud.info("Section \(index + 1): type=\(section.type), title=\(section.title), yStart=\(section.yStart), yEnd=\(section.yEnd)")
                    AppLogger.cloud.info("  Content preview: \(section.content.prefix(100))...")
                }

                // Convert to our format
                let analysisResult = Self.convertToAnalysisResult(cloudResult)
                AppLogger.cloud.info("Converted to \(analysisResult.exercises.count) exercises")

                // Log final exercises
                for (index, exercise) in analysisResult.exercises.enumerated() {
                    AppLogger.cloud.info("Exercise \(index + 1): #\(exercise.exerciseNumber), type=\(exercise.type), subject=\(exercise.subject ?? "N/A"), startY=\(String(format: "%.3f", exercise.startY)), endY=\(String(format: "%.3f", exercise.endY))")
                }

                completion(.success(analysisResult))
            } catch {
                AppLogger.cloud.error("❌ Decoding failed for text-only analysis", error: error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLogger.cloud.error("Raw response causing error: \(jsonString.prefix(500))...")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }

    // MARK: - Future Multi-Image Endpoint
    // TODO: Uncomment this method once the cloud function is deployed
    // This will send multiple images separately to the cloud for better analysis

    /*
    /// Performs the actual multi-image analysis request with the given App Check token
    private func performMultiImageAnalysisRequest(
        images: [UIImage],
        ocrBlocks: [OCRBlock],
        appCheckToken: String,
        completion: @escaping (Result<AnalysisResult, Error>) -> Void,
        retryCount: Int = 0
    ) {
        // Step 1: Convert all images to base64
        var imageDataArray: [MultiImageAnalysisRequest.ImageData] = []

        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                completion(.failure(CloudAnalysisError.imageConversionFailed))
                return
            }
            let imageBase64 = imageData.base64EncodedString()
            imageDataArray.append(MultiImageAnalysisRequest.ImageData(
                imageBase64: imageBase64,
                imageMimeType: "image/jpeg",
                pageNumber: index + 1
            ))
        }

        // Step 2: Format OCR blocks as text with coordinates
        let ocrJsonText = self.formatOCRBlocks(ocrBlocks)

        // Step 3: Create request
        let requestBody = MultiImageAnalysisRequest(
            images: imageDataArray,
            ocrJsonText: ocrJsonText
        )

        // Step 4: Call Firebase endpoint with App Check token
        let url = URL(string: "\(Config.baseURL)/analyzeHomeworkMultiPage")!
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

        AppLogger.cloud.info("Sending multi-image analysis request to \(url.absoluteString)")
        AppLogger.cloud.info("Analyzing \(images.count) pages")
        AppLogger.cloud.debug("OCR text length: \(ocrJsonText.count) characters")
        AppLogger.cloud.debug("Request size: \(request.httpBody?.count ?? 0) bytes")
        if retryCount > 0 {
            AppLogger.cloud.info("Retry attempt \(retryCount) of \(Config.maxRetries)")
        }

        // Step 5: Execute request with custom session
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                AppLogger.cloud.error("Network error in multi-image analysis", error: error)
                AppLogger.cloud.debug("Error domain: \(nsError.domain), code: \(nsError.code)")

                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performMultiImageAnalysisRequest(
                            images: images,
                            ocrBlocks: ocrBlocks,
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

            AppLogger.cloud.debug("Multi-image response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Server returned error: \(errorMessage)")

                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1) of \(Config.maxRetries)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performMultiImageAnalysisRequest(
                            images: images,
                            ocrBlocks: ocrBlocks,
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

            // Decode and convert
            do {
                let cloudResult = try JSONDecoder().decode(CloudAnalysisResult.self, from: data)
                AppLogger.cloud.info("Successfully decoded multi-image response - Summary: \(cloudResult.summary)")
                AppLogger.cloud.debug("Found \(cloudResult.sections.count) sections across \(images.count) pages")

                // Convert to our format
                let analysisResult = Self.convertToAnalysisResult(cloudResult)
                AppLogger.cloud.info("Converted to \(analysisResult.exercises.count) exercises from \(images.count) pages")

                completion(.success(analysisResult))
            } catch {
                AppLogger.cloud.error("Multi-image decoding failed", error: error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLogger.cloud.debug("Raw response: \(jsonString.prefix(500))")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }
    */

    /// Formats OCR blocks into text format for the cloud API
    private func formatOCRBlocks(_ blocks: [OCRBlock]) -> String {
        var result = "OCR Text Analysis with Y-coordinates:\n\n"

        for (index, block) in blocks.enumerated() {
            let yCoord = Int(block.y * 1000) // Convert normalized to integer
            result += "Block \(index + 1) (Y: \(yCoord)): \(block.text)\n"
        }

        return result
    }

    /// Converts cloud response to our internal format
    private static func convertToAnalysisResult(_ cloudResult: CloudAnalysisResult) -> AnalysisResult {
        var exercises: [Exercise] = []

        AppLogger.cloud.debug("Converting cloud result to exercises...")
        AppLogger.cloud.debug("Total sections: \(cloudResult.sections.count)")

        for (_, section) in cloudResult.sections.enumerated() {
            // Normalize Y coordinates back to 0-1 range
            let startY = Double(section.yStart) / 1000.0
            let endY = Double(section.yEnd) / 1000.0

            if section.type == "EXERCISE" {
                // Extract exercise number from title (e.g., "Exercise 8" -> "8")
                let exerciseNumber = extractExerciseNumber(from: section.title)
                let exercise = Exercise(
                    exerciseNumber: exerciseNumber,
                    type: inferExerciseType(from: section.content),
                    fullContent: addBackslashesToLaTeX(section.content),
                    startY: startY,
                    endY: endY,
                    subject: section.subject,
                    inputType: section.inputType
                )
                exercises.append(exercise)

                // Log exercise details with corrected content
                let subjectStr = section.subject ?? "N/A"
                let inputTypeStr = section.inputType ?? "N/A"
                AppLogger.cloud.info("Exercise #\(exerciseNumber): Subject=\(subjectStr), Input=\(inputTypeStr), Type=\(exercise.type), startY=\(String(format: "%.3f", startY)), endY=\(String(format: "%.3f", endY))")
                AppLogger.cloud.debug("Content (from LLM): \(section.content.prefix(100))...")
            } else {
                AppLogger.cloud.debug("Skipping section type: \(section.type)")
            }
        }

        // Sort by Y position (ascending for top-to-bottom order)
        // New coordinate system: Y=0 is top, Y=1000 is bottom, so lower startY = higher on page
        let sortedExercises = exercises.sorted { $0.startY < $1.startY }
        AppLogger.cloud.info("Successfully converted to \(sortedExercises.count) exercises")

        return AnalysisResult(exercises: sortedExercises)
    }

    private static func addBackslashesToLaTeX(_ text: String) -> String {
        if text.contains("\\frac") {
            return "\\(" + text + "\\)"
        }
        return text
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

    /// Generates progressive hints for an exercise using cloud AI
    ///
    /// - Parameters:
    ///   - exercise: The exercise to generate hints for
    ///   - completion: Callback with array of 4 progressive hints
    func generateHints(
        for exercise: Exercise,
        completion: @escaping (Result<[Hint], Error>) -> Void
    ) {
        #if DEBUG
        let appCheckToken = "emulator-bypass-token"
        AppLogger.cloud.info("DEBUG mode: Using emulator bypass token for hints generation")
        performHintsRequest(exercise: exercise, appCheckToken: appCheckToken, completion: completion)
        #else
        AppLogger.cloud.info("RELEASE mode: Getting App Check token for hints generation...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.cloud.error("App Check token error for hints", error: error)
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.cloud.error("No App Check token received for hints")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.cloud.info("App Check token obtained for hints generation")

            self.performHintsRequest(exercise: exercise, appCheckToken: appCheckToken, completion: completion)
        }
        #endif
    }

    /// Generates similar practice exercises based on an existing exercise
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
        #if DEBUG
        let appCheckToken = "emulator-bypass-token"
        AppLogger.cloud.info("DEBUG mode: Using emulator bypass token for similar exercises generation")
        performSimilarExercisesRequest(exercise: exercise, count: count, appCheckToken: appCheckToken, completion: completion)
        #else
        AppLogger.cloud.info("RELEASE mode: Getting App Check token for similar exercises generation...")
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                AppLogger.cloud.error("App Check token error for similar exercises", error: error)
                completion(.failure(CloudAnalysisError.appCheckFailed(error)))
                return
            }

            guard let token = token else {
                AppLogger.cloud.error("No App Check token received for similar exercises")
                completion(.failure(CloudAnalysisError.noAppCheckToken))
                return
            }

            let appCheckToken = token.token
            AppLogger.cloud.info("App Check token obtained for similar exercises generation")

            self.performSimilarExercisesRequest(exercise: exercise, count: count, appCheckToken: appCheckToken, completion: completion)
        }
        #endif
    }

    /// Performs the actual similar exercises generation request
    private func performSimilarExercisesRequest(
        exercise: Exercise,
        count: Int,
        appCheckToken: String,
        completion: @escaping (Result<[SimilarExercise], Error>) -> Void,
        retryCount: Int = 0
    ) {
        let url = FirebaseConfig.Endpoint.generateSimilarExercises.url
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")

        // Create request body
        let requestBody: [String: Any] = [
            "exerciseNumber": exercise.exerciseNumber,
            "exerciseType": exercise.type,
            "exerciseContent": exercise.fullContent,
            "subject": exercise.subject ?? "general",
            "count": count
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(CloudAnalysisError.encodingFailed(error)))
            return
        }

        AppLogger.cloud.info("Sending similar exercises request to \(url.absoluteString)")
        if retryCount > 0 {
            AppLogger.cloud.info("Retry attempt \(retryCount) of \(Config.maxRetries)")
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                AppLogger.cloud.error("Network error in similar exercises request", error: error)

                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performSimilarExercisesRequest(
                            exercise: exercise,
                            count: count,
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

            AppLogger.cloud.debug("Similar exercises response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Similar exercises error response: \(errorMessage)")

                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performSimilarExercisesRequest(
                            exercise: exercise,
                            count: count,
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

            do {
                let exercises = try JSONDecoder().decode([SimilarExercise].self, from: data)
                AppLogger.cloud.info("Successfully decoded \(exercises.count) similar exercises")
                completion(.success(exercises))
            } catch {
                AppLogger.cloud.error("Similar exercises decoding error", error: error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLogger.cloud.debug("Raw response: \(jsonString.prefix(500))")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }

    /// Performs the actual hints generation request
    private func performHintsRequest(
        exercise: Exercise,
        appCheckToken: String,
        completion: @escaping (Result<[Hint], Error>) -> Void,
        retryCount: Int = 0
    ) {
        let url = FirebaseConfig.Endpoint.generateHints.url
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")

        // Create request body
        let requestBody: [String: Any] = [
            "exerciseNumber": exercise.exerciseNumber,
            "exerciseType": exercise.type,
            "exerciseContent": exercise.fullContent,
            "subject": exercise.subject ?? "general"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(CloudAnalysisError.encodingFailed(error)))
            return
        }

        AppLogger.cloud.info("Sending hints request to \(url.absoluteString)")
        if retryCount > 0 {
            AppLogger.cloud.info("Retry attempt \(retryCount) of \(Config.maxRetries)")
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                AppLogger.cloud.error("Network error in hints request", error: error)

                let isRetryableError = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut ||
                     nsError.code == NSURLErrorNetworkConnectionLost ||
                     nsError.code == NSURLErrorCannotConnectToHost)

                if isRetryableError && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Retryable error detected, scheduling retry \(retryCount + 1)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performHintsRequest(
                            exercise: exercise,
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

            AppLogger.cloud.debug("Hints response status code: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                AppLogger.cloud.error("Hints error response: \(errorMessage)")

                if httpResponse.statusCode >= 500 && retryCount < Config.maxRetries {
                    AppLogger.cloud.info("Server error (5xx), scheduling retry \(retryCount + 1)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.retryDelay) {
                        self.performHintsRequest(
                            exercise: exercise,
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

            do {
                let hints = try JSONDecoder().decode([Hint].self, from: data)
                AppLogger.cloud.info("Successfully decoded \(hints.count) hints")
                completion(.success(hints))
            } catch {
                AppLogger.cloud.error("Hints decoding error", error: error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    AppLogger.cloud.debug("Raw response: \(jsonString.prefix(500))")
                }
                completion(.failure(CloudAnalysisError.decodingFailed(error)))
            }
        }

        task.resume()
    }
}