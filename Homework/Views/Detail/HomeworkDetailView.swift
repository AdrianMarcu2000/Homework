//
//  HomeworkDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

/// Protocol for types that can trigger homework analysis
protocol HomeworkAnalyzer {
    var isAnalyzing: Bool { get }
    var analysisProgress: (current: Int, total: Int)? { get }

    func analyzeWithAppleAI(homework: any AnalyzableHomework)
    func analyzeWithCloudAI(homework: any AnalyzableHomework)
    func analyzeWithAgenticAI(homework: any AnalyzableHomework)
}

/// A generic detail view that works with any AnalyzableHomework type
struct HomeworkDetailView<Homework: AnalyzableHomework>: View {
    var homework: Homework
    @Binding var showExercises: Bool
    var analyzer: (any HomeworkAnalyzer)?

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @AppStorage("useAgenticAnalysis") private var useAgenticAnalysis = false
    @State private var isReanalyzing = false
    @State private var refreshTrigger = false

    // Check if already analyzed
    private var hasAnalysis: Bool {
        homework.analysisResult != nil && !(homework.analysisResult?.exercises.isEmpty ?? true)
    }

    private var isAnalyzing: Bool {
        analyzer?.isAnalyzing ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            if isAnalyzing {
                // Show progress indicator during analysis
                analysisProgressView
            } else {
                // Split view: Content ↔ Exercises with animated transitions
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Left side: Homework content (only shown when not showing exercises)
                        if !showExercises {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .trailing) {
                                    homeworkContentScrollView
                                        .frame(width: geometry.size.width)

                                    // Floating Exercises button - right middle
                                    if hasAnalysis, let analysis = homework.analysisResult {
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
                        if showExercises, let analysis = homework.analysisResult, !analysis.exercises.isEmpty {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .leading) {
                                    ScrollView {
                                        VStack(spacing: 16) {
                                            // Exercises content
                                            ForEach(analysis.exercises, id: \.self) { exercise in
                                                ExerciseCardView(exercise: exercise, homework: homework)
                                                    .padding(.horizontal, 20)
                                            }
                                        }
                                        .padding(.bottom)
                                    }
                                    .frame(width: geometry.size.width)
                                    .background(Color(UIColor.systemBackground))

                                    // Back button - aligned to middle-left
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Navigation button
                                        Button(action: {
                                            AppLogger.ui.info("User navigated to homework content from exercises")
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                showExercises = false
                                            }
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "chevron.left")
                                                    .font(.system(size: 16, weight: .semibold))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Homework")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                    Text("View content")
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

                                        // Compact preview thumbnail
                                        if let imageData = homework.imageData, let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxWidth: 120, maxHeight: 100)
                                                .cornerRadius(6)
                                                .shadow(radius: 2)
                                        } else if let extractedText = homework.extractedText, !extractedText.isEmpty {
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
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Analysis Progress

    private var analysisProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = analyzer?.analysisProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Homework Content Scroll View

    private var homeworkContentScrollView: some View {
        ScrollView {
            HomeworkContentView(homework: homework)
                .padding(.vertical)
        }
        .navigationTitle(homework.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HomeworkToolbarTitle(homework: homework)
            }

            // AI analysis toolbar buttons
            if analyzer != nil {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Apple AI button
                    if AIAnalysisService.shared.isModelAvailable {
                        Button(action: {
                            AppLogger.ui.info("User tapped analyze with Apple AI")
                            isReanalyzing = true
                            analyzer?.analyzeWithAppleAI(homework: homework)
                        }) {
                            Image(systemName: "apple.logo")
                                .font(.body)
                        }
                        .disabled(isAnalyzing)
                    }

                    // Agentic AI button
                    if useAgenticAnalysis {
                        Button(action: {
                            AppLogger.ui.info("User tapped analyze with Agentic AI")
                            isReanalyzing = true
                            analyzer?.analyzeWithAgenticAI(homework: homework)
                        }) {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                        .disabled(isAnalyzing)
                    }

                    // Google AI button
                    if useCloudAnalysis {
                        Button(action: {
                            AppLogger.ui.info("User tapped analyze with Cloud AI")
                            isReanalyzing = true
                            analyzer?.analyzeWithCloudAI(homework: homework)
                        }) {
                            Image(systemName: "cloud")
                                .font(.body)
                        }
                        .disabled(isAnalyzing)
                    }
                }
            }
        }
    }
}
