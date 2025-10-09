//
//  SimilarExercisesView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI

/// A view that displays AI-generated similar practice exercises
struct SimilarExercisesView: View {
    let originalExercise: AIAnalysisService.Exercise
    @Environment(\.dismiss) var dismiss

    @State private var similarExercises: [AIAnalysisService.SimilarExercise] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Original Exercise Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original Exercise")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        OriginalExerciseCard(exercise: originalExercise)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Similar Exercises Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Similar Practice Exercises")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        if isLoading {
                            LoadingView()
                        } else if let error = errorMessage {
                            ErrorView(message: error) {
                                generateExercises()
                            }
                        } else if similarExercises.isEmpty {
                            EmptyStateView {
                                generateExercises()
                            }
                        } else {
                            ForEach(similarExercises) { exercise in
                                SimilarExerciseCard(exercise: exercise)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Practice Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(GlassmorphicButtonStyle())
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: generateExercises) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassmorphicButtonStyle())
                    .disabled(isLoading)
                }
            }
        }
        .onAppear {
            if similarExercises.isEmpty {
                generateExercises()
            }
        }
    }

    private func generateExercises() {
        isLoading = true
        errorMessage = nil

        AIAnalysisService.shared.generateSimilarExercises(
            basedOn: originalExercise,
            count: 3
        ) { result in
            isLoading = false

            switch result {
            case .success(let exercises):
                similarExercises = exercises
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Supporting Views

/// Card displaying the original exercise
private struct OriginalExerciseCard: View {
    let exercise: AIAnalysisService.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Exercise \(exercise.exerciseNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                Spacer()
                Text(exercise.type.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(8)
            }

            Text(exercise.fullContent)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 2)
        )
    }
}

/// Card displaying a similar exercise with difficulty indicator
private struct SimilarExerciseCard: View {
    let exercise: AIAnalysisService.SimilarExercise

    private var difficultyColor: Color {
        switch exercise.difficulty.lowercased() {
        case "easier": return .green
        case "harder": return .red
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Practice \(exercise.exerciseNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(difficultyColor)
                Spacer()
                HStack(spacing: 4) {
                    difficultyIcon
                    Text(exercise.difficulty.capitalized)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(difficultyColor.opacity(0.2))
                .cornerRadius(8)
            }

            Text(exercise.content)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(.primary)
        }
        .padding()
        .background(difficultyColor.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(difficultyColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var difficultyIcon: some View {
        Group {
            switch exercise.difficulty.lowercased() {
            case "easier":
                Image(systemName: "arrow.down.circle.fill")
            case "harder":
                Image(systemName: "arrow.up.circle.fill")
            default:
                Image(systemName: "equal.circle.fill")
            }
        }
        .foregroundColor(difficultyColor)
        .font(.caption)
    }
}

/// Loading view with spinner
private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating practice exercises...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Error view with retry button
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Empty state view
private struct EmptyStateView: View {
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Generate Similar Exercises")
                .font(.headline)
            Text("Tap the button to generate practice exercises similar to the original")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Generate", action: onGenerate)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Previews

#Preview {
    let mockExercise = AIAnalysisService.Exercise(
        exerciseNumber: "1",
        type: "mathematical",
        fullContent: "Solve for x: 2x + 5 = 15",
        startY: 0.3,
        endY: 0.35
    )

    SimilarExercisesView(originalExercise: mockExercise)
}
