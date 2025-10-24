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
    weak var assignment: ClassroomAssignment?

    func analyzeWithAppleAI(homework: any AnalyzableHomework) {
        guard let assignment = homework as? ClassroomAssignment else { return }
        analyzeAppleAI?(assignment)
    }

    func analyzeWithCloudAI(homework: any AnalyzableHomework) {
        guard let assignment = homework as? ClassroomAssignment else { return }
        analyzeCloudAI?(assignment)
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
            analyzer.assignment = assignment
            analyzer.analyzeAppleAI = { assignment in
                analyzeWithAI(useCloud: false)
            }
            analyzer.analyzeCloudAI = { assignment in
                analyzeWithAI(useCloud: true)
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

    private func analyzeWithAI(useCloud: Bool) {
        AppLogger.ui.info("User tapped analyze with \(useCloud ? "Google" : "Apple") AI")

        Task {
            await startAnalysis()

            do {
                let images = try await assignment.downloadAllAttachments()
                await performAnalysis(images: images, useCloud: useCloud)
            } catch {
                // Fallback to text-only analysis if download fails
                await performTextOnlyAnalysis(useCloud: useCloud, error: error)
            }
        }
    }

    /// Unified analysis method that routes to appropriate HomeworkAnalysisService method
    private func performAnalysis(images: [UIImage], useCloud: Bool) async {
        let config = createAnalysisConfig(useCloud: useCloud)

        // Determine analysis type based on image count
        if images.isEmpty {
            await performTextOnlyAnalysis(useCloud: useCloud)
        } else if images.count == 1 {
            HomeworkAnalysisService.analyzeImage(images[0], configuration: config, completion: handleAnalysisOutput)
        } else {
            HomeworkAnalysisService.analyzeImages(images, configuration: config, completion: handleAnalysisOutput)
        }
    }

    /// Performs text-only analysis with fallback logic
    private func performTextOnlyAnalysis(useCloud: Bool, error: Error? = nil) async {
        // Try extracted text first, then assignment description
        let textToAnalyze = assignment.extractedText?.nilIfEmpty
                         ?? assignment.coursework.description?.nilIfEmpty

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
        HomeworkAnalysisService.analyzeTextOnly(text, useCloud: useCloud, completion: handleAnalysisOutput)
    }

    /// Creates analysis configuration with progress tracking
    private func createAnalysisConfig(useCloud: Bool) -> HomeworkAnalysisService.AnalysisConfiguration {
        var config = HomeworkAnalysisService.AnalysisConfiguration()
        config.useCloud = useCloud
        config.additionalContext = assignment.coursework.description
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
    private func handleAnalysisOutput(_ result: Result<HomeworkAnalysisService.AnalysisOutput, Error>) {
        DispatchQueue.main.async {
            analyzer.isAnalyzing = false
            analyzer.analysisProgress = nil

            switch result {
            case .success(let output):
                // Save analysis result
                assignment.extractedText = output.extractedText
                if let imageData = output.imageData {
                    assignment.imageData = imageData
                }

                do {
                    try assignment.saveAnalysis(output.analysisResult)
                    AppLogger.persistence.info("Analysis saved - Exercises: \(output.analysisResult.exercises.count)")
                } catch {
                    AppLogger.persistence.error("Error saving analysis", error: error)
                }

                // Navigate to exercises view after successful analysis
                showExercises = true

            case .failure(let error):
                analysisError = error.localizedDescription
                AppLogger.ai.error("Analysis failed", error: error)
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
