
//
//  HomeworkDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

/// A detail view for displaying a single homework item's information.
struct HomeworkDetailView: View {
    let item: Item
    var viewModel: HomeworkCaptureViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var showExercises = false
    @State private var isReanalyzing = false

    // Check if already analyzed
    private var hasAnalysis: Bool {
        item.analysisResult != nil && !(item.analysisResult?.exercises.isEmpty ?? true)
    }

    var body: some View {
        if showExercises && hasAnalysis {
            // Show exercises view
            exercisesView
        } else {
            // Show homework overview with image and analyze buttons
            homeworkOverviewView
        }
    }

    // MARK: - Exercises View

    private var exercisesView: some View {
        VStack(spacing: 0) {
            if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                analysisProgressView
            } else if let analysis = item.analysisResult {
                VStack(spacing: 0) {
                    // Custom navigation bar
                    HStack {
                        Button(action: { showExercises = false }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .padding()

                        Spacer()

                        Text("Exercises")
                            .font(.headline)

                        Spacer()

                        // Invisible button for symmetry
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .padding()
                        .opacity(0)
                    }
                    .background(Color(UIColor.systemBackground))

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(analysis.exercises, id: \.exerciseNumber) { exercise in
                                HomeworkDetailExerciseCard(exercise: exercise, homeworkItem: item)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Analysis Progress

    private var analysisProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = viewModel.analysisProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text(viewModel.isCloudAnalysisInProgress ? "Analyzing with cloud AI..." : "Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Homework Overview

    private var homeworkOverviewView: some View {
        VStack(spacing: 0) {
            if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                // Show progress
                analysisProgressView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display scanned image in main body
                        if let imageData = item.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding()
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No Image")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }

                        // AI Analysis / Re-analyze buttons
                        VStack(spacing: 12) {
                            Text(hasAnalysis ? "Actions" : "Analyze with AI")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                // Apple AI button
                                if AIAnalysisService.shared.isModelAvailable {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Apple AI")
                                        isReanalyzing = true
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "apple.logo")
                                                .font(.title2)
                                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                                .font(.caption)
                                            if !hasAnalysis {
                                                Text("Apple AI")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, hasAnalysis ? 12 : 16)
                                        .background(Color.purple.opacity(0.1))
                                        .foregroundColor(.purple)
                                        .cornerRadius(10)
                                    }
                                    .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                                }

                                // Google AI button
                                if useCloudAnalysis {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Cloud AI")
                                        isReanalyzing = true
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "cloud.fill")
                                                .font(.title2)
                                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                                .font(.caption)
                                            if !hasAnalysis {
                                                Text("Google AI")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, hasAnalysis ? 12 : 16)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(10)
                                    }
                                    .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                                }

                                // View Exercises button (only when analyzed)
                                if hasAnalysis {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped view exercises")
                                        showExercises = true
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "pencil.and.list.clipboard")
                                                .font(.title2)
                                            Text("View Exercises")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Homework Details")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.isProcessingOCR) { _, newValue in
            if !newValue && !viewModel.isCloudAnalysisInProgress {
                isReanalyzing = false
            }
        }
        .onChange(of: viewModel.isCloudAnalysisInProgress) { _, newValue in
            if !newValue && !viewModel.isProcessingOCR {
                isReanalyzing = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Homework Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let timestamp = item.timestamp {
                        Text(timestamp, formatter: itemFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Text Analysis

    /// Analyze text-only homework using AI (no image available)
    private func analyzeTextOnly(text: String) {
        AppLogger.ai.info("Starting text-only AI analysis for local homework")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    AppLogger.ai.info("Text analysis complete with \(analysis.exercises.count) exercises")

                    // Save the analysis
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(analysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            self.item.analysisJSON = jsonString
                            try self.viewContext.save()
                            AppLogger.persistence.info("Text-only analysis saved to Core Data")
                        }
                    } catch {
                        AppLogger.persistence.error("Failed to save text-only analysis", error: error)
                    }

                case .failure(let error):
                    AppLogger.ai.error("Text analysis failed", error: error)
                }
            }
        }
    }
}
private struct HomeworkDetailExerciseCard: View {
    let exercise: Exercise
    let homeworkItem: Item

    var body: some View {
        ExerciseCardContent(
            exercise: exercise,
            imageData: homeworkItem.imageData,
            exerciseAnswers: Binding(
                get: { homeworkItem.exerciseAnswers },
                set: { homeworkItem.exerciseAnswers = $0 }
            )
        )
    }
}
