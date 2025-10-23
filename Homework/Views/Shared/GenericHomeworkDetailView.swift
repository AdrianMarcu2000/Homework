//
//  GenericHomeworkDetailView.swift
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
}

/// A generic detail view that works with any AnalyzableHomework type
struct GenericHomeworkDetailView<Homework: AnalyzableHomework>: View {
    var homework: Homework
    @Binding var showExercises: Bool
    var analyzer: (any HomeworkAnalyzer)?

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
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
            if isAnalyzing {
                analysisProgressView
            } else if let analysis = homework.analysisResult {
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
                                GenericExerciseCard(exercise: exercise, homework: homework)
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

    // MARK: - Homework Overview

    private var homeworkOverviewView: some View {
        VStack(spacing: 0) {
            if isAnalyzing {
                // Show progress
                analysisProgressView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display scanned image in main body
                        if let imageData = homework.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding()
                        } else if let extractedText = homework.extractedText, !extractedText.isEmpty {
                            // Show text preview if no image
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Extracted Text")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text(extractedText)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineLimit(10)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .padding(.horizontal)
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
                        if analyzer != nil {
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
                                            analyzer?.analyzeWithAppleAI(homework: homework)
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
                                        .disabled(isAnalyzing)
                                    }

                                    // Google AI button
                                    if useCloudAnalysis {
                                        Button(action: {
                                            AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Cloud AI")
                                            isReanalyzing = true
                                            analyzer?.analyzeWithCloudAI(homework: homework)
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
                                        .disabled(isAnalyzing)
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
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(homework.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(homework.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let date = homework.date {
                        Text(date, formatter: itemFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// Generic exercise card that works with any AnalyzableHomework type
private struct GenericExerciseCard<Homework: AnalyzableHomework>: View {
    let exercise: Exercise
    var homework: Homework

    var body: some View {
        ExerciseCardContent(
            exercise: exercise,
            imageData: homework.imageData,
            exerciseAnswers: Binding(
                get: { homework.exerciseAnswers },
                set: { homework.exerciseAnswers = $0 }
            )
        )
    }
}
