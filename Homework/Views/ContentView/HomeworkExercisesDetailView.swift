
//
//  HomeworkExercisesDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

/// A simplified detail view that shows exercises directly without intermediate tabs
struct HomeworkExercisesDetailView: View {
    @ObservedObject var item: Item
    var viewModel: HomeworkCaptureViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @AppStorage("hasCloudSubscription") private var hasCloudSubscription = false
    @State private var isReanalyzing = false
    @State private var showingSettings = false
    @State private var showExercises = false

    /// Determines which AI upgrade button to show based on analysis history and AI availability
    private func getUpgradeOption() -> (show: Bool, method: AnalysisMethod, label: String, icon: String, color: Color, opensSettings: Bool)? {
        let currentMethod = item.usedAnalysisMethod
        let appleAvailable = AIAnalysisService.shared.isModelAvailable
        let cloudEnabled = useCloudAnalysis

        // If already using cloud AI, no upgrade available
        if currentMethod == .cloudAI {
            return nil
        }

        // Case 1: User has subscription and cloud is enabled - show "Analyze with AI"
        if hasCloudSubscription && cloudEnabled {
            // Only show if not already analyzed with cloud
            if currentMethod != .cloudAI {
                return (true, .cloudAI, "Analyze with AI", "cloud.fill", .orange, false)
            }
        }

        // Case 2: User has subscription but cloud is disabled - show "Enable AI" (opens settings)
        if hasCloudSubscription && !cloudEnabled {
            return (true, .cloudAI, "Enable AI", "cloud.fill", .orange, true)
        }

        // Case 3: No subscription - show "Enable AI" (opens settings to subscribe)
        if !hasCloudSubscription && currentMethod != .cloudAI {
            return (true, .cloudAI, "Enable AI", "cloud.fill", .orange, true)
        }

        // Case 4: If Apple AI is available and not used yet, suggest Apple AI
        if appleAvailable && currentMethod != .appleAI && !cloudEnabled {
            return (true, .appleAI, "Analyze with AI", "apple.logo", .orange, false)
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                // Show progress indicator during reanalysis
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
            } else {
                // Split view: Active view takes 75%, inactive sidebar 25%
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Left side: Original content (only shown when not showing exercises)
                        if !showExercises {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .trailing) {
                                    ScrollView {
                                        VStack(spacing: 20) {
                                            // Original image/text
                                            if item.imageData != nil, let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(12)
                                                    .shadow(radius: 5)
                                                    .padding(.horizontal)
                                            } else if let extractedText = item.extractedText, !extractedText.isEmpty {
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Text("Extracted Text")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                        .padding(.horizontal)

                                                    Text(extractedText)
                                                        .font(.body)
                                                        .foregroundColor(.primary)
                                                        .textSelection(.enabled)
                                                        .padding()
                                                        .background(Color(UIColor.secondarySystemBackground))
                                                        .cornerRadius(12)
                                                        .padding(.horizontal)
                                                }
                                            } else {
                                                VStack(spacing: 16) {
                                                    Image(systemName: "doc.text.image")
                                                        .font(.system(size: 48))
                                                        .foregroundColor(.secondary)
                                                    Text("No Content")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 60)
                                            }
                                        }
                                        .padding(.vertical)
                                    }
                                    .frame(width: geometry.size.width)

                                    // Floating Exercises button - right middle (only when not showing exercises)
                                    if let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                                        Button(action: {
                                            AppLogger.ui.info("User opened exercises panel")
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                showExercises = true
                                            }
                                        }) {
                                            HStack(spacing: 10) {
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Exercises")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                    Text("\(analysis.exercises.count) found")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.blue.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(16)
                                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: -2, y: 0)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 24)
                                        .position(x: contentGeometry.size.width - 100, y: contentGeometry.size.height / 2)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
                            .frame(width: geometry.size.width)
                        }

                        // Right side: Exercises panel (full width when showing)
                        if showExercises, let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .leading) {
                                    ScrollView {
                                        VStack(spacing: 16) {
                                            // Exercises content
                                            LessonsAndExercisesView(analysis: analysis, homeworkItem: item)
                                                .padding(.horizontal, 20)
                                        }
                                        .padding(.bottom)
                                    }
                                    .frame(width: geometry.size.width)
                                    .background(Color(UIColor.systemBackground))

                                    // Back button - aligned to middle-left at same vertical position as Exercises button
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Navigation button
                                        Button(action: {
                                            AppLogger.ui.info("User navigated to original from exercises")
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                showExercises = false
                                            }
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "chevron.left")
                                                    .font(.system(size: 16, weight: .semibold))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Original")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                    Text("View homework")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.blue.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(16)
                                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 2, y: 0)
                                        }
                                        .buttonStyle(.plain)

                                        // Compact thumbnail preview
                                        if item.imageData != nil, let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxWidth: 120, maxHeight: 100)
                                                .cornerRadius(6)
                                                .shadow(radius: 2)
                                        } else if let extractedText = item.extractedText, !extractedText.isEmpty {
                                            Text(extractedText)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(5)
                                                .padding(8)
                                                .frame(maxWidth: 120, alignment: .leading)
                                                .background(Color(UIColor.secondarySystemBackground))
                                                .cornerRadius(6)
                                        }
                                    }
                                    .padding(.leading, 24)
                                    .position(x: 100, y: contentGeometry.size.height / 2)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: geometry.size.width)
                            .id(item.analysisJSON ?? "")
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        // Apple AI button
                        if item.analysisStatus != .inProgress && AIAnalysisService.shared.isModelAvailable {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                            }) {
                                Image(systemName: "apple.logo")
                                    .font(.body)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }

                        // Google AI button
                        if useCloudAnalysis && item.analysisStatus != .inProgress {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                            }) {
                                Image(systemName: "cloud")
                                    .font(.body)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }
                    }
                }
            }
        }
        
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
                    Text(item.title)
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(BiometricAuthService.shared)
        }
        .id(item.id)  // Reset view state when item changes
    }

    // MARK: - Text Analysis

    /// Analyze text-only homework using AI (no image available)
    private func analyzeTextOnly(text: String) {
        AppLogger.ai.info("Starting text analysis for local homework")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    AppLogger.ai.info("Text analysis complete - Found \(analysis.exercises.count) exercises")

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
                        AppLogger.persistence.error("Error saving text-only analysis", error: error)
                    }

                case .failure(let error):
                    AppLogger.ai.error("Text analysis failed", error: error)
                }
            }
        }
    }
}
