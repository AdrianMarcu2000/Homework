//
//  AssignmentDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import PencilKit
import Combine
import OSLog

/// Analyzer wrapper for ClassroomAssignment to work with HomeworkDetailView
private class AssignmentAnalyzer: ObservableObject, HomeworkAnalyzer {
    @Published var isAnalyzing = false
    @Published var analysisProgress: (current: Int, total: Int)?

    var analyzeAppleAI: ((ClassroomAssignment) -> Void)?
    var analyzeCloudAI: ((ClassroomAssignment) -> Void)?
    var analyzeAgenticAI: ((ClassroomAssignment) -> Void)?
    weak var assignment: ClassroomAssignment?

    func analyzeWithAppleAI(homework: any AnalyzableHomework) {
        guard let assignment = homework as? ClassroomAssignment else { return }
        analyzeAppleAI?(assignment)
    }

    func analyzeWithCloudAI(homework: any AnalyzableHomework) {
        guard let assignment = homework as? ClassroomAssignment else { return }
        analyzeCloudAI?(assignment)
    }

    func analyzeWithAgenticAI(homework: any AnalyzableHomework) {
        guard let assignment = homework as? ClassroomAssignment else { return }
        analyzeAgenticAI?(assignment)
    }
}

/// View for displaying and analyzing a Google Classroom assignment
struct AssignmentDetailView: View {
    @ObservedObject var assignment: ClassroomAssignment
    @StateObject private var analyzer = AssignmentAnalyzer()
    @State private var analysisError: String?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var showExercises = false
    @State private var contentRefreshTrigger = UUID()

    var body: some View {
        // Use unified HomeworkDetailView
        HomeworkDetailView(
            homework: assignment,
            showExercises: $showExercises,
            analyzer: analyzer
        )
        .id("\(assignment.id)_\(contentRefreshTrigger)")
        .onAppear {
            AppLogger.ui.info("📱 AssignmentDetailView appeared for: \(assignment.title) (ID: \(assignment.id))")
            AppLogger.ui.info("📊 Assignment state - imageData: \(assignment.imageData != nil) (\(assignment.imageData?.count ?? 0) bytes), extractedText: \(assignment.extractedText != nil) (\(assignment.extractedText?.count ?? 0) chars)")

            // Setup analyzer callbacks
            // IMPORTANT: These closures receive the assignment parameter from the analyzer,
            // which is the CURRENT assignment from the button press, not a captured reference
            analyzer.analyzeAppleAI = { passedAssignment in
                // Verify we're analyzing the correct assignment
                AppLogger.ui.info("Analyzer callback received assignment: \(passedAssignment.title) (ID: \(passedAssignment.id))")
                analyzeAssignment(passedAssignment, useCloud: false, useAgentic: false)
            }
            analyzer.analyzeCloudAI = { passedAssignment in
                AppLogger.ui.info("Analyzer callback received assignment: \(passedAssignment.title) (ID: \(passedAssignment.id))")
                analyzeAssignment(passedAssignment, useCloud: true, useAgentic: false)
            }
            analyzer.analyzeAgenticAI = { passedAssignment in
                AppLogger.ui.info("Analyzer callback received assignment: \(passedAssignment.title) (ID: \(passedAssignment.id))")
                analyzeAssignment(passedAssignment, useCloud: false, useAgentic: true)
            }

            // Download attachments for display if not already downloaded
            if assignment.imageData == nil && assignment.extractedText == nil {
                AppLogger.ui.info("🔽 Starting download - no content available yet")
                downloadAttachmentsForDisplay()
            } else {
                AppLogger.ui.info("✅ Content already available - skipping download")
            }
        }
    }

    // MARK: - Analysis Actions

    private func analyzeAssignment(_ assignmentToAnalyze: ClassroomAssignment, useCloud: Bool, useAgentic: Bool = false) {
        let aiType = useAgentic ? "Agentic" : (useCloud ? "Google" : "Apple")
        AppLogger.ui.info("User tapped analyze with \(aiType) AI for assignment: \(assignmentToAnalyze.title) (ID: \(assignmentToAnalyze.id))")

        Task {
            await startAnalysis()

            do {
                AppLogger.ui.info("📥 Downloading attachments for analysis - Assignment: \(assignmentToAnalyze.title)")
                let images = try await assignmentToAnalyze.downloadAllAttachments()
                AppLogger.ui.info("✅ Downloaded \(images.count) image(s) for analysis")
                await performAnalysis(assignmentToAnalyze, images: images, useCloud: useCloud, useAgentic: useAgentic)
            } catch {
                // Fallback to text-only analysis if download fails
                await performTextOnlyAnalysis(assignmentToAnalyze, useCloud: useCloud, useAgentic: useAgentic, error: error)
            }
        }
    }

    /// Unified analysis method that routes to appropriate analysis service
    private func performAnalysis(_ assignmentToAnalyze: ClassroomAssignment, images: [UIImage], useCloud: Bool, useAgentic: Bool = false) async {
        // Route to agentic service if requested
        if useAgentic {
            await performAgenticAnalysis(assignmentToAnalyze, images: images)
            return
        }

        let config = createAnalysisConfig(assignmentToAnalyze, useCloud: useCloud, useAgentic: useAgentic)

        // Determine analysis type based on image count
        if images.isEmpty {
            await performTextOnlyAnalysis(assignmentToAnalyze, useCloud: useCloud, useAgentic: useAgentic)
        } else if images.count == 1 {
            HomeworkAnalysisService.analyzeImage(images[0], configuration: config, completion: { result in
                self.handleAnalysisOutput(assignmentToAnalyze, result: result)
            })
        } else {
            HomeworkAnalysisService.analyzeImages(images, configuration: config, completion: { result in
                self.handleAnalysisOutput(assignmentToAnalyze, result: result)
            })
        }
    }

    /// Performs text-only analysis with fallback logic
    private func performTextOnlyAnalysis(_ assignmentToAnalyze: ClassroomAssignment, useCloud: Bool, useAgentic: Bool = false, error: Error? = nil) async {
        // Try extracted text first, then assignment description
        let textToAnalyze = assignmentToAnalyze.extractedText?.nilIfEmpty
                         ?? assignmentToAnalyze.coursework.description?.nilIfEmpty

        guard let text = textToAnalyze else {
            await MainActor.run {
                analyzer.isAnalyzing = false
                analysisError = "This assignment has no content to analyze. Please add a description or attach files."
                if let error = error {
                    AppLogger.google.error("No content available for analysis", error: error)
                }
            }
            return
        }

        AppLogger.ai.info("Using text-only analysis (\(text.count) chars)")
        // TODO: HomeworkAnalysisService doesn't support agentic yet, fallback to cloud
        HomeworkAnalysisService.analyzeTextOnly(text, useCloud: useCloud || useAgentic, completion: { result in
            self.handleAnalysisOutput(assignmentToAnalyze, result: result)
        })
    }

    /// Performs agentic (multi-agent) analysis using specialized agents
    private func performAgenticAnalysis(_ assignmentToAnalyze: ClassroomAssignment, images: [UIImage]) async {
        AppLogger.cloud.info("Starting agentic analysis for: \(assignmentToAnalyze.title) with \(images.count) images")

        // Combine multiple images if needed
        let imageToAnalyze: UIImage
        if images.count > 1 {
            // Combine images vertically
            imageToAnalyze = images[0] // TODO: Implement image combining if needed
        } else if images.count == 1 {
            imageToAnalyze = images[0]
        } else {
            await MainActor.run {
                analyzer.isAnalyzing = false
                analysisError = "No images available for agentic analysis"
            }
            return
        }

        // Capture references for closures
        let currentAssignment = assignmentToAnalyze
        let currentAnalyzer = analyzer

        // Perform OCR first
        OCRService.shared.recognizeTextWithBlocks(from: imageToAnalyze) { result in
            switch result {
            case .success(let ocrResult):
                AppLogger.ocr.info("OCR completed with \(ocrResult.blocks.count) blocks for agentic analysis")

                // Convert OCR blocks to AI service format
                let aiBlocks = ocrResult.blocks.map { block in
                    OCRBlock(text: block.text, y: block.y)
                }

                // Call agentic service
                AgenticCloudAnalysisService.shared.analyzeHomework(
                    image: imageToAnalyze,
                    ocrBlocks: aiBlocks
                ) { agenticResult in
                    DispatchQueue.main.async {
                        currentAnalyzer.isAnalyzing = false

                        switch agenticResult {
                        case .success(let agenticResponse):
                            AppLogger.cloud.info("Agentic analysis successful - Subject: \(agenticResponse.routing.subject), Agent: \(agenticResponse.routing.agentUsed)")

                            // Convert agentic response to standard AnalysisResult
                            let analysis = agenticResponse.toAnalysisResult()

                            // Save analysis
                            do {
                                try currentAssignment.saveAnalysis(analysis)
                                AppLogger.persistence.info("Agentic analysis saved - Exercises: \(analysis.exercises.count)")

                                // Update extracted text with routing info
                                currentAssignment.extractedText = """
                                    Subject: \(agenticResponse.routing.subject)
                                    Type: \(agenticResponse.routing.contentType)
                                    Agent: \(agenticResponse.routing.agentUsed)
                                    Found \(analysis.exercises.count) exercise(s)
                                    """
                            } catch {
                                AppLogger.persistence.error("Failed to save agentic analysis", error: error)
                            }

                        case .failure(let error):
                            AppLogger.cloud.error("Agentic analysis failed", error: error)
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    currentAnalyzer.isAnalyzing = false
                    AppLogger.ocr.error("OCR failed during agentic analysis", error: error)
                }
            }
        }
    }

    /// Creates analysis configuration with progress tracking
    private func createAnalysisConfig(_ assignmentToAnalyze: ClassroomAssignment, useCloud: Bool, useAgentic: Bool = false) -> HomeworkAnalysisService.AnalysisConfiguration {
        var config = HomeworkAnalysisService.AnalysisConfiguration()
        // TODO: HomeworkAnalysisService doesn't support agentic yet, fallback to cloud
        config.useCloud = useCloud || useAgentic
        config.additionalContext = assignmentToAnalyze.coursework.description
        config.onProgress = { current, total in
            DispatchQueue.main.async {
                self.analyzer.analysisProgress = (current, total)
            }
        }
        return config
    }

    /// Starts analysis state
    private func startAnalysis() async {
        await MainActor.run {
            analyzer.isAnalyzing = true
            analysisError = nil
            analyzer.analysisProgress = nil
        }
    }

    /// Handles analysis output from unified HomeworkAnalysisService
    private func handleAnalysisOutput(_ assignmentToAnalyze: ClassroomAssignment, result: Result<HomeworkAnalysisService.AnalysisOutput, Error>) {
        DispatchQueue.main.async {
            self.analyzer.isAnalyzing = false
            self.analyzer.analysisProgress = nil

            switch result {
            case .success(let output):
                // Save analysis result to the correct assignment
                assignmentToAnalyze.extractedText = output.extractedText
                if let imageData = output.imageData {
                    assignmentToAnalyze.imageData = imageData
                }

                do {
                    try assignmentToAnalyze.saveAnalysis(output.analysisResult)
                    AppLogger.persistence.info("Analysis saved for \(assignmentToAnalyze.title) - Exercises: \(output.analysisResult.exercises.count)")
                } catch {
                    AppLogger.persistence.error("Error saving analysis for \(assignmentToAnalyze.title)", error: error)
                }

                // Navigate to exercises view after successful analysis
                self.showExercises = true

            case .failure(let error):
                self.analysisError = error.localizedDescription
                AppLogger.ai.error("Analysis failed for \(assignmentToAnalyze.title)", error: error)
            }
        }
    }

    // MARK: - Content Download

    /// Downloads attachments for display without triggering analysis
    private func downloadAttachmentsForDisplay() {
        AppLogger.google.info("🔽 downloadAttachmentsForDisplay started")
        Task {
            do {
                let images = try await assignment.downloadAllAttachments()
                await MainActor.run {
                    AppLogger.google.info("✅ Download complete - \(images.count) images")
                    AppLogger.google.info("📊 After download - imageData: \(assignment.imageData != nil) (\(assignment.imageData?.count ?? 0) bytes), extractedText: \(assignment.extractedText != nil) (\(assignment.extractedText?.count ?? 0) chars)")

                    // Force view refresh by updating trigger
                    let oldTrigger = contentRefreshTrigger
                    contentRefreshTrigger = UUID()
                    AppLogger.ui.info("🔄 Triggered content refresh - old: \(oldTrigger), new: \(contentRefreshTrigger)")

                    // Also manually trigger objectWillChange to ensure SwiftUI notices
                    assignment.objectWillChange.send()
                    AppLogger.ui.info("🔄 Sent objectWillChange notification")
                }
            } catch {
                await MainActor.run {
                    AppLogger.google.error("❌ Failed to download attachments for display", error: error)
                    AppLogger.google.error("Error details: \(error.localizedDescription)")
                }
                // Silently fail - user can still view attachments list and try analysis
            }
        }
    }

}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
