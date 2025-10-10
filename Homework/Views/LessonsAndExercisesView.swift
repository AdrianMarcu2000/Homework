//
//  LessonsAndExercisesView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// A view that displays analyzed exercises from homework
struct LessonsAndExercisesView: View {
    let analysis: AIAnalysisService.AnalysisResult
    let homeworkItem: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary
            SummaryCard(
                icon: "pencil.circle.fill",
                title: "Exercises",
                count: analysis.exercises.count,
                color: .green
            )

            // Exercises Section
            if !analysis.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("✏️ Exercises")
                        .font(.title3)
                        .fontWeight(.bold)

                    ForEach(Array(analysis.exercises.enumerated()), id: \.offset) { index, exercise in
                        ExerciseCard(exercise: exercise, homeworkItem: homeworkItem)
                    }
                }
            }

            // Empty state
            if analysis.exercises.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No exercises found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            }
        }
    }
}

/// Summary card showing count of items
private struct SummaryCard: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Card displaying an exercise
struct ExerciseCard: View {
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: Item
    @State private var showSimilarExercises = false
    @State private var showHints = false
    @State private var canvasData: Data?

    /// Computed property to get the cropped image for this exercise
    private var croppedExerciseImage: UIImage? {
        guard let imageData = homeworkItem.imageData,
              let fullImage = UIImage(data: imageData) else {
            return nil
        }
        return fullImage.crop(startY: exercise.startY, endY: exercise.endY, padding: 0.03)
    }

    init(exercise: AIAnalysisService.Exercise, homeworkItem: Item) {
        self.exercise = exercise
        self.homeworkItem = homeworkItem
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)"
        _canvasData = State(initialValue: homeworkItem.exerciseAnswers?[key])
    }

    /// Computed view that returns the appropriate input method based on exercise type
    @ViewBuilder
    private var answerInputView: some View {
        let inputType = exercise.inputType ?? "canvas" // default to canvas if not specified
        let isMath = exercise.subject == "mathematics"

        switch inputType {
        case "inline":
            // Inline fill-in-the-blank input
            InlineAnswerView(exercise: exercise, homeworkItem: homeworkItem)

        case "text":
            // Simple text input for short answers
            TextAnswerView(exercise: exercise, homeworkItem: homeworkItem)

        case "canvas":
            // Canvas for showing work - use math notebook style for math
            if isMath {
                MathNotebookCanvasView(exercise: exercise, homeworkItem: homeworkItem, canvasData: $canvasData)
            } else {
                DrawingCanvasView(exercise: exercise, homeworkItem: homeworkItem, canvasData: $canvasData)
            }

        case "both":
            // Both canvas and text input
            VStack(spacing: 12) {
                if isMath {
                    MathNotebookCanvasView(exercise: exercise, homeworkItem: homeworkItem, canvasData: $canvasData)
                } else {
                    DrawingCanvasView(exercise: exercise, homeworkItem: homeworkItem, canvasData: $canvasData)
                }
                TextAnswerView(exercise: exercise, homeworkItem: homeworkItem)
            }

        default:
            // Fallback to canvas
            DrawingCanvasView(exercise: exercise, homeworkItem: homeworkItem, canvasData: $canvasData)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text("Exercise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    Text(exercise.exerciseNumber)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                Spacer()

                // Input type badge
                if let inputType = exercise.inputType {
                    HStack(spacing: 4) {
                        Image(systemName: inputTypeIcon(inputType))
                            .font(.caption2)
                        Text(inputType.capitalized)
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(inputTypeColor(inputType).opacity(0.2))
                    .foregroundColor(inputTypeColor(inputType))
                    .cornerRadius(6)
                }

                Text(exercise.type.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            }

            // Cropped exercise image
            if let croppedImage = croppedExerciseImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
            }

            Text(exercise.fullContent)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(.primary)

            // Action buttons
            HStack(spacing: 8) {
                // Hints button
                Button(action: { showHints = true }) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                        Text("Give me a hint")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.yellow, Color.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Practice button
                Button(action: { showSimilarExercises = true }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Practice with similar exercises")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Answer input area based on inputType
            Divider()
                .padding(.vertical, 4)

            answerInputView
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showSimilarExercises) {
            SimilarExercisesView(originalExercise: exercise)
        }
        .sheet(isPresented: $showHints) {
            HintsView(exercise: exercise)
        }
    }

    // MARK: - Helper Functions

    /// Returns the SF Symbol icon for the input type
    private func inputTypeIcon(_ inputType: String) -> String {
        switch inputType {
        case "inline": return "pencil.line"
        case "text": return "text.cursor"
        case "canvas": return "pencil.tip"
        case "both": return "square.split.2x1"
        default: return "questionmark"
        }
    }

    /// Returns the color for the input type badge
    private func inputTypeColor(_ inputType: String) -> Color {
        switch inputType {
        case "inline": return .orange
        case "text": return .green
        case "canvas": return .blue
        case "both": return .purple
        default: return .gray
        }
    }
}

// MARK: - Previews

#Preview {
    let mockAnalysis = AIAnalysisService.AnalysisResult(
        exercises: [
            AIAnalysisService.Exercise(
                exerciseNumber: "1",
                type: "mathematical",
                fullContent: "Solve for x: 2x + 5 = 15",
                startY: 0.3,
                endY: 0.35
            ),
            AIAnalysisService.Exercise(
                exerciseNumber: "2",
                type: "calculation",
                fullContent: "Calculate the area of a rectangle with length 8 cm and width 5 cm",
                startY: 0.4,
                endY: 0.45
            )
        ]
    )

    let mockItem: Item = {
        let context = PersistenceController.preview.container.viewContext
        let item = Item(context: context)
        item.timestamp = Date()
        // Create a simple white image for preview
        if let mockImage = UIImage(systemName: "doc.text")?.withTintColor(.black, renderingMode: .alwaysOriginal),
           let imageData = mockImage.pngData() {
            item.imageData = imageData
        }
        return item
    }()

    return ScrollView {
        LessonsAndExercisesView(analysis: mockAnalysis, homeworkItem: mockItem)
            .padding()
    }
}
