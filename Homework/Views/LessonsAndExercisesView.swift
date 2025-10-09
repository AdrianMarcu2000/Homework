//
//  LessonsAndExercisesView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// A view that displays analyzed lessons and exercises from homework
struct LessonsAndExercisesView: View {
    let analysis: AIAnalysisService.AnalysisResult
    let homeworkItem: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary
            HStack(spacing: 16) {
                SummaryCard(
                    icon: "book.fill",
                    title: "Lessons",
                    count: analysis.lessons.count,
                    color: .blue
                )
                SummaryCard(
                    icon: "pencil.circle.fill",
                    title: "Exercises",
                    count: analysis.exercises.count,
                    color: .green
                )
            }

            // Lessons Section
            if !analysis.lessons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("📚 Lessons")
                        .font(.title3)
                        .fontWeight(.bold)

                    ForEach(Array(analysis.lessons.enumerated()), id: \.offset) { index, lesson in
                        LessonCard(lesson: lesson, index: index + 1)
                    }
                }
            }

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
            if analysis.lessons.isEmpty && analysis.exercises.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No lessons or exercises found")
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

/// Card displaying a lesson
struct LessonCard: View {
    let lesson: AIAnalysisService.Lesson
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lesson \(index)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Spacer()
                Text("Y: \(String(format: "%.2f", lesson.startY))-\(String(format: "%.2f", lesson.endY))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(lesson.topic)
                .font(.headline)

            Text(lesson.fullContent)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Card displaying an exercise
struct ExerciseCard: View {
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: Item
    @State private var showSimilarExercises = false
    @State private var showHints = false
    @State private var canvasData: Data?

    init(exercise: AIAnalysisService.Exercise, homeworkItem: Item) {
        self.exercise = exercise
        self.homeworkItem = homeworkItem
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)"
        _canvasData = State(initialValue: homeworkItem.exerciseAnswers?[key])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Text(exercise.type.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
            }

            HStack {
                Spacer()
                Text("Y: \(String(format: "%.2f", exercise.startY))-\(String(format: "%.2f", exercise.endY))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                        Text("Hints")
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
                        Text("Practice")
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

            // Drawing canvas for answer
            Divider()
                .padding(.vertical, 4)

            DrawingCanvasView(
                exercise: exercise,
                homeworkItem: homeworkItem,
                canvasData: $canvasData
            )
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
}

// MARK: - Previews

#Preview {
    let mockAnalysis = AIAnalysisService.AnalysisResult(
        lessons: [
            AIAnalysisService.Lesson(
                topic: "Introduction to Algebra",
                fullContent: "Algebra is a branch of mathematics dealing with symbols and the rules for manipulating those symbols.",
                startY: 0.1,
                endY: 0.25
            )
        ],
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
        return item
    }()

    return ScrollView {
        LessonsAndExercisesView(analysis: mockAnalysis, homeworkItem: mockItem)
            .padding()
    }
}
