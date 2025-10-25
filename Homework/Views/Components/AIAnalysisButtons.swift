//
//  AIAnalysisButtons.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

/// Shared AI analysis button row
struct AIAnalysisButtons: View {
    var hasAnalysis: Bool
    var isAnalyzing: Bool
    var onAnalyzeWithApple: () -> Void
    var onAnalyzeWithCloud: () -> Void
    var onAnalyzeWithAgentic: (() -> Void)?
    var onViewExercises: (() -> Void)?

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @AppStorage("useAgenticAnalysis") private var useAgenticAnalysis = false

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

                // Agentic AI button
                if useAgenticAnalysis, let agenticAction = onAnalyzeWithAgentic {
                    Button(action: {
                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Agentic AI")
                        agenticAction()
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                .font(.caption)
                            if !hasAnalysis {
                                Text("Agentic AI")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, hasAnalysis ? 12 : 16)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
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
