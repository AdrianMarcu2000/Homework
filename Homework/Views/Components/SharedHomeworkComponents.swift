//
//  SharedHomeworkComponents.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

// MARK: - Analysis Progress View

/// Shared analysis progress view that works with any analyzer
struct AnalysisProgressView: View {
    var progress: (current: Int, total: Int)?
    var isCloudAnalysis: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = progress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text(isCloudAnalysis ? "Analyzing with cloud AI..." : "Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }
}

// MARK: - Homework Image/Content Display

/// Shared homework content display (image or text)
struct HomeworkContentView<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
        let _ = {
            let hasImageData = homework.imageData != nil
            let imageDataSize = homework.imageData?.count ?? 0
            let hasExtractedText = homework.extractedText != nil
            let extractedTextLength = homework.extractedText?.count ?? 0
            let hasDescription = (homework as? ClassroomAssignment)?.coursework.description != nil
            let descriptionLength = (homework as? ClassroomAssignment)?.coursework.description?.count ?? 0

            AppLogger.ui.info("📄 HomeworkContentView rendering - imageData: \(hasImageData) (\(imageDataSize) bytes), extractedText: \(hasExtractedText) (\(extractedTextLength) chars), description: \(hasDescription) (\(descriptionLength) chars)")
        }()

        VStack(spacing: 20) {
            // Show assignment description first if it's a ClassroomAssignment
            if let assignment = homework as? ClassroomAssignment,
               let description = assignment.coursework.description,
               !description.isEmpty {
                let _ = AppLogger.ui.info("✅ Displaying assignment description (\(description.count) chars)")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Assignment")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            }

            // Show attached image content if available
            if let imageData = homework.imageData,
               let uiImage = UIImage(data: imageData) {
                let _ = AppLogger.ui.info("✅ Displaying attached image (\(imageData.count) bytes)")

                if homework is ClassroomAssignment {
                    Text("Attachments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding(.horizontal)
            } else if let extractedText = homework.extractedText, !extractedText.isEmpty {
                // For non-ClassroomAssignment items, show extracted text
                let _ = AppLogger.ui.info("✅ Displaying extracted text content (\(extractedText.count) chars)")
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
            } else if !(homework is ClassroomAssignment) || (homework as? ClassroomAssignment)?.coursework.description?.isEmpty ?? true {
                // Only show "No Content" if there's truly no content
                let _ = AppLogger.ui.info("⚠️ Showing 'No Content' - no description, imageData, or extractedText available")
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
    }
}

// MARK: - AI Analysis Buttons

/// Shared AI analysis button row
struct AIAnalysisButtons: View {
    var hasAnalysis: Bool
    var isAnalyzing: Bool
    var onAnalyzeWithApple: () -> Void
    var onAnalyzeWithCloud: () -> Void
    var onViewExercises: (() -> Void)?

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var body: some View {
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
                        onAnalyzeWithApple()
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
                        onAnalyzeWithCloud()
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
                if hasAnalysis, let viewExercises = onViewExercises {
                    Button(action: {
                        AppLogger.ui.info("User tapped view exercises")
                        viewExercises()
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

// MARK: - Exercises List

/// Shared exercises list view
struct ExercisesListView<Homework: AnalyzableHomework>: View {
    var analysis: AnalysisResult
    var homework: Homework
    var onAnswerChange: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(analysis.exercises, id: \.self) { exercise in
                    ExerciseCardView(
                        exercise: exercise,
                        homework: homework,
                        onAnswerChange: onAnswerChange
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Toolbar Title

/// Shared toolbar title view for homework items
struct HomeworkToolbarTitle<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
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
