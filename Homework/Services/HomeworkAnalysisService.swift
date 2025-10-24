//
//  HomeworkAnalysisService.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import UIKit
import Combine
import OSLog

/// Unified service for analyzing homework with OCR + AI
/// Eliminates duplicate analysis logic across AssignmentDetailView and HomeworkCaptureViewModel
class HomeworkAnalysisService {

    /// Analysis configuration
    struct AnalysisConfiguration {
        var useCloud: Bool = false
        var additionalContext: String? = nil  // e.g., assignment description
        var onProgress: ((Int, Int) -> Void)? = nil
    }

    /// Analysis result with metadata
    struct AnalysisOutput {
        let analysisResult: AnalysisResult
        let extractedText: String
        let imageData: Data?
        let ocrBlocks: [OCRBlock]
    }

    // MARK: - Single Image Analysis

    /// Analyzes a single image with OCR + AI
    static func analyzeImage(
        _ image: UIImage,
        configuration: AnalysisConfiguration = AnalysisConfiguration(),
        completion: @escaping (Result<AnalysisOutput, Error>) -> Void
    ) {
        // Resize image for display (detail view size) - this is what we'll store
        let displayImage = image.resized(for: .detailView)

        // Further resize for LLM processing to reduce API payload
        let llmImage = displayImage.resizedForLLM()

        // Perform OCR on display image (better quality than LLM-sized)
        OCRService.shared.recognizeTextWithBlocks(from: displayImage) { result in
            switch result {
            case .success(let ocrResult):
                // Prepare OCR blocks with optional additional context
                var aiBlocks = ocrResult.blocks.map { OCRBlock(text: $0.text, y: $0.y) }

                var combinedText = ocrResult.fullText

                // Add additional context (e.g., assignment description) as top block
                if let context = configuration.additionalContext, !context.isEmpty {
                    let contextBlock = OCRBlock(
                        text: "Assignment Description:\n\(context)\n\nAttachment Content:",
                        y: 1.0
                    )
                    aiBlocks.insert(contextBlock, at: 0)
                    combinedText = "Assignment Description:\n\(context)\n\nAttachment Content:\n\(ocrResult.fullText)"
                    AppLogger.ai.info("Added context (\(context.count) chars) to OCR (\(ocrResult.fullText.count) chars)")
                }

                // Store display-sized image data (optimized for viewing)
                let imageData = displayImage.jpegData(compressionQuality: 0.85)

                // Perform AI analysis with LLM-sized image (smaller for faster processing)
                if configuration.useCloud {
                    analyzeWithCloud(
                        image: llmImage,
                        ocrBlocks: aiBlocks,
                        extractedText: combinedText,
                        imageData: imageData,
                        completion: completion
                    )
                } else {
                    analyzeWithLocal(
                        image: llmImage,
                        ocrBlocks: aiBlocks,
                        extractedText: combinedText,
                        imageData: imageData,
                        progressHandler: configuration.onProgress,
                        completion: completion
                    )
                }

            case .failure(let error):
                AppLogger.ocr.error("OCR failed", error: error)
                completion(.failure(error))
            }
        }
    }

    // MARK: - Multiple Images Analysis

    /// Analyzes multiple images by combining them
    static func analyzeImages(
        _ images: [UIImage],
        configuration: AnalysisConfiguration = AnalysisConfiguration(),
        completion: @escaping (Result<AnalysisOutput, Error>) -> Void
    ) {
        // Combine images
        guard let combinedImage = PDFProcessingService.shared.combineImages(images, spacing: 20) else {
            let error = NSError(
                domain: "HomeworkAnalysis",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to combine images"]
            )
            AppLogger.image.error("Failed to combine \(images.count) images", error: error)
            completion(.failure(error))
            return
        }

        AppLogger.image.info("Combined \(images.count) images successfully")

        // Analyze combined image - always use cloud for multi-image
        var cloudConfig = configuration
        cloudConfig.useCloud = true

        analyzeImage(combinedImage, configuration: cloudConfig, completion: completion)
    }

    // MARK: - Text-Only Analysis

    /// Analyzes text without an image
    static func analyzeTextOnly(
        _ text: String,
        useCloud: Bool = false,
        completion: @escaping (Result<AnalysisOutput, Error>) -> Void
    ) {
        AppLogger.ai.info("Starting text-only analysis (\(text.count) chars) with \(useCloud ? "cloud" : "local") AI")

        let analysisCompletion: (Result<AnalysisResult, Error>) -> Void = { result in
            switch result {
            case .success(let analysis):
                let output = AnalysisOutput(
                    analysisResult: analysis,
                    extractedText: text,
                    imageData: nil,
                    ocrBlocks: []
                )
                completion(.success(output))

            case .failure(let error):
                completion(.failure(error))
            }
        }

        if useCloud {
            CloudAnalysisService.shared.analyzeTextOnly(text: text, completion: analysisCompletion)
        } else {
            AIAnalysisService.shared.analyzeTextOnly(text: text, completion: analysisCompletion)
        }
    }

    // MARK: - Private Helpers

    private static func analyzeWithLocal(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        extractedText: String,
        imageData: Data?,
        progressHandler: ((Int, Int) -> Void)?,
        completion: @escaping (Result<AnalysisOutput, Error>) -> Void
    ) {
        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: ocrBlocks,
            progressHandler: progressHandler
        ) { result in
            switch result {
            case .success(let analysis):
                let output = AnalysisOutput(
                    analysisResult: analysis,
                    extractedText: extractedText,
                    imageData: imageData,
                    ocrBlocks: ocrBlocks
                )
                AppLogger.ai.info("Local analysis complete - Found \(analysis.exercises.count) exercises")
                completion(.success(output))

            case .failure(let error):
                AppLogger.ai.error("Local analysis failed", error: error)
                completion(.failure(error))
            }
        }
    }

    private static func analyzeWithCloud(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        extractedText: String,
        imageData: Data?,
        completion: @escaping (Result<AnalysisOutput, Error>) -> Void
    ) {
        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: ocrBlocks
        ) { result in
            switch result {
            case .success(let analysis):
                let output = AnalysisOutput(
                    analysisResult: analysis,
                    extractedText: extractedText,
                    imageData: imageData,
                    ocrBlocks: ocrBlocks
                )
                AppLogger.cloud.info("Cloud analysis complete - Found \(analysis.exercises.count) exercises")
                completion(.success(output))

            case .failure(let error):
                AppLogger.cloud.error("Cloud analysis failed", error: error)
                completion(.failure(error))
            }
        }
    }
}
