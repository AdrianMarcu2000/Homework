//
//  HintsView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI

/// A view that displays progressive hints for an exercise
struct HintsView: View {
    let exercise: AIAnalysisService.Exercise
    @Environment(\.dismiss) var dismiss

    @State private var hints: [AIAnalysisService.Hint] = []
    @State private var currentHintLevel = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Hints")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(GlassmorphicButtonStyle())
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: resetHints) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(GlassmorphicButtonStyle())
                        .disabled(isLoading || currentHintLevel == 0)
                    }
                }
        }
        .onAppear {
            if hints.isEmpty {
                generateHints()
            }
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Exercise Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercise")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    ExerciseInfoCard(exercise: exercise)
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Hints Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("Progressive Hints")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    if isLoading {
                        LoadingView()
                    } else if let error = errorMessage {
                        ErrorView(message: error) {
                            generateHints()
                        }
                    } else if hints.isEmpty {
                        EmptyStateView {
                            generateHints()
                        }
                    } else {
                        // Show revealed hints
                        ForEach(hints.filter { $0.level <= currentHintLevel }) { hint in
                            HintCard(hint: hint)
                                .padding(.horizontal)
                        }

                        // Show button to reveal next hint
                        if currentHintLevel < hints.count {
                            Button(action: revealNextHint) {
                                HStack {
                                    Image(systemName: "lightbulb")
                                    Text(currentHintLevel == 0 ? "Show First Hint" : "Show Next Hint")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
    }

    private func generateHints() {
        isLoading = true
        errorMessage = nil

        AIAnalysisService.shared.generateHints(for: exercise) { result in
            isLoading = false

            switch result {
            case .success(let generatedHints):
                hints = generatedHints.sorted { $0.level < $1.level }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revealNextHint() {
        withAnimation {
            currentHintLevel += 1
        }
    }

    private func resetHints() {
        withAnimation {
            currentHintLevel = 0
        }
    }
}

// MARK: - Supporting Views

/// Card displaying the exercise information
private struct ExerciseInfoCard: View {
    let exercise: AIAnalysisService.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Exercise \(exercise.exerciseNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Spacer()
                Text(exercise.type.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }

            Text(exercise.fullContent)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
        )
    }
}

/// Card displaying a hint
private struct HintCard: View {
    let hint: AIAnalysisService.Hint

    private var levelColor: Color {
        switch hint.level {
        case 1: return .green
        case 2: return .orange
        case 3: return .red
        default: return .gray
        }
    }

    private var levelIcon: String {
        switch hint.level {
        case 1: return "1.circle.fill"
        case 2: return "2.circle.fill"
        case 3: return "3.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var levelDescription: String {
        switch hint.level {
        case 1: return "Basic Hint"
        case 2: return "Method Hint"
        case 3: return "Detailed Hint"
        default: return "Hint"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: levelIcon)
                    .foregroundColor(levelColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(levelDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hint.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(levelColor)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(hint.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundColor(.primary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(levelColor.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(levelColor.opacity(0.3), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Loading view with spinner
private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating hints...")
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
            Image(systemName: "lightbulb")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Get Help with This Exercise")
                .font(.headline)
            Text("Tap below to start receiving progressive hints")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Start Hints", action: onGenerate)
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

    HintsView(exercise: mockExercise)
}
