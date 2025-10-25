//
//  AnalysisRouter.swift
//  Homework
//
//  Routing utility to determine which analysis service to use
//  based on user preferences and system capabilities
//

import UIKit
import Foundation
import OSLog

/// Router that decides which analysis service to use based on settings and availability
class AnalysisRouter {
    static let shared = AnalysisRouter()

    private init() {}

    /// Analysis service types
    enum AnalysisService {
        case onDevice // Apple Intelligence (iOS 18.1+)
        case cloudSingleAgent // Current cloud analysis
        case cloudAgentic // New multi-agent cloud analysis
    }

    /// Determines which analysis service to use based on current settings
    ///
    /// - Returns: The recommended analysis service
    func determineAnalysisService() -> AnalysisService {
        let settings = AppSettings.shared

        // Priority 1: Agentic cloud analysis (if enabled and subscription active)
        if settings.useAgenticAnalysis && settings.hasCloudSubscription {
            AppLogger.ai.info("Using agentic (multi-agent) cloud analysis")
            return .cloudAgentic
        }

        // Priority 2: Regular cloud analysis (if enabled and subscription active)
        if settings.useCloudAnalysis && settings.hasCloudSubscription {
            AppLogger.ai.info("Using single-agent cloud analysis")
            return .cloudSingleAgent
        }

        // Priority 3: On-device Apple Intelligence (default if available)
        if AIAnalysisService.shared.isModelAvailable {
            AppLogger.ai.info("Using on-device Apple Intelligence")
            return .onDevice
        }

        // Fallback: Cloud analysis (requires subscription)
        AppLogger.ai.warning("Apple Intelligence not available, falling back to cloud analysis")
        return .cloudSingleAgent
    }

    /// Analyzes homework using the appropriate service based on settings
    ///
    /// - Parameters:
    ///   - image: The homework image
    ///   - ocrBlocks: OCR text blocks
    ///   - progressHandler: Optional progress callback for segment-based analysis
    ///   - completion: Callback with analysis result and metadata
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        progressHandler: ((Int, Int) -> Void)? = nil,
        completion: @escaping (Result<AnalysisResultWithMetadata, Error>) -> Void
    ) {
        let service = determineAnalysisService()

        switch service {
        case .onDevice:
            analyzeWithOnDevice(
                image: image,
                ocrBlocks: ocrBlocks,
                progressHandler: progressHandler,
                completion: completion
            )

        case .cloudSingleAgent:
            analyzeWithCloudSingleAgent(
                image: image,
                ocrBlocks: ocrBlocks,
                completion: completion
            )

        case .cloudAgentic:
            analyzeWithCloudAgentic(
                image: image,
                ocrBlocks: ocrBlocks,
                completion: completion
            )
        }
    }

    /// Async version of analyzeHomework
    func analyzeHomework(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> Result<AnalysisResultWithMetadata, Error> {
        return await withCheckedContinuation { continuation in
            analyzeHomework(
                image: image,
                ocrBlocks: ocrBlocks,
                progressHandler: progressHandler
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Private Analysis Methods

    private func analyzeWithOnDevice(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        progressHandler: ((Int, Int) -> Void)?,
        completion: @escaping (Result<AnalysisResultWithMetadata, Error>) -> Void
    ) {
        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: ocrBlocks,
            progressHandler: progressHandler
        ) { result in
            switch result {
            case .success(let analysisResult):
                let metadata = AnalysisMetadata(
                    serviceUsed: "On-Device Apple Intelligence",
                    processingTimeMs: nil,
                    routing: nil,
                    agentsInvoked: nil
                )
                let resultWithMetadata = AnalysisResultWithMetadata(
                    result: analysisResult,
                    metadata: metadata
                )
                completion(.success(resultWithMetadata))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func analyzeWithCloudSingleAgent(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        completion: @escaping (Result<AnalysisResultWithMetadata, Error>) -> Void
    ) {
        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: ocrBlocks
        ) { result in
            switch result {
            case .success(let analysisResult):
                let metadata = AnalysisMetadata(
                    serviceUsed: "Cloud (Single Agent)",
                    processingTimeMs: nil,
                    routing: nil,
                    agentsInvoked: ["single_agent"]
                )
                let resultWithMetadata = AnalysisResultWithMetadata(
                    result: analysisResult,
                    metadata: metadata
                )
                completion(.success(resultWithMetadata))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func analyzeWithCloudAgentic(
        image: UIImage,
        ocrBlocks: [OCRBlock],
        completion: @escaping (Result<AnalysisResultWithMetadata, Error>) -> Void
    ) {
        // Use default user preferences (can be customized in the future)
        let userPreferences = AgenticAnalysisRequest.UserPreferences(
            detailLevel: "detailed",
            includeExtraPractice: true,
            preferredLanguage: "en"
        )

        AgenticCloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: ocrBlocks,
            userPreferences: userPreferences
        ) { result in
            switch result {
            case .success(let agenticResponse):
                // Convert agentic response to standard AnalysisResult
                let analysisResult = agenticResponse.toAnalysisResult()

                // Create metadata from agentic response
                let routing = RoutingMetadata(
                    subject: agenticResponse.routing.subject,
                    contentType: agenticResponse.routing.contentType,
                    gradeLevel: agenticResponse.routing.gradeLevel,
                    confidence: agenticResponse.routing.confidence,
                    agentUsed: agenticResponse.routing.agentUsed
                )

                let metadata = AnalysisMetadata(
                    serviceUsed: "Cloud (Multi-Agent)",
                    processingTimeMs: agenticResponse.metadata.processingTimeMs,
                    routing: routing,
                    agentsInvoked: agenticResponse.metadata.agentsInvoked,
                    agenticResponse: agenticResponse // Store full agentic response
                )

                let resultWithMetadata = AnalysisResultWithMetadata(
                    result: analysisResult,
                    metadata: metadata,
                    agenticResponse: agenticResponse // Pass through for UI components
                )

                completion(.success(resultWithMetadata))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Analysis Result with Metadata

/// Wrapper that combines AnalysisResult with metadata about how it was processed
struct AnalysisResultWithMetadata {
    let result: AnalysisResult
    let metadata: AnalysisMetadata
    let agenticResponse: AgenticAnalysisResponse? // Full agentic response if available

    init(result: AnalysisResult, metadata: AnalysisMetadata, agenticResponse: AgenticAnalysisResponse? = nil) {
        self.result = result
        self.metadata = metadata
        self.agenticResponse = agenticResponse
    }
}

/// Metadata about the analysis process
struct AnalysisMetadata {
    let serviceUsed: String // "On-Device Apple Intelligence", "Cloud (Single Agent)", "Cloud (Multi-Agent)"
    let processingTimeMs: Int?
    let routing: RoutingMetadata?
    let agentsInvoked: [String]?
    let agenticResponse: AgenticAnalysisResponse? // Store full agentic response for advanced UI

    init(
        serviceUsed: String,
        processingTimeMs: Int?,
        routing: RoutingMetadata?,
        agentsInvoked: [String]?,
        agenticResponse: AgenticAnalysisResponse? = nil
    ) {
        self.serviceUsed = serviceUsed
        self.processingTimeMs = processingTimeMs
        self.routing = routing
        self.agentsInvoked = agentsInvoked
        self.agenticResponse = agenticResponse
    }
}

/// Routing metadata from agentic analysis
struct RoutingMetadata {
    let subject: String
    let contentType: String
    let gradeLevel: String
    let confidence: Double
    let agentUsed: String
}
