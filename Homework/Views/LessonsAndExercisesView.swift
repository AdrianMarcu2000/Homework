//
//  LessonsAndExercisesView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import PencilKit
import OSLog

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

                    // Log exercise coordinates for debugging
                    let _ = {
                        AppLogger.ui.info("📝 Exercise coordinates:")
                        for exercise in analysis.exercises {
                            AppLogger.ui.info("  Exercise #\(exercise.exerciseNumber): startY=\(String(format: "%.3f", exercise.startY)), endY=\(String(format: "%.3f", exercise.endY))")
                        }
                        AppLogger.ui.info("📝 After sorting by startY ascending:")
                        for exercise in analysis.exercises.sorted(by: { $0.startY < $1.startY }) {
                            AppLogger.ui.info("  Exercise #\(exercise.exerciseNumber): startY=\(String(format: "%.3f", exercise.startY)), endY=\(String(format: "%.3f", exercise.endY))")
                        }
                    }()

                    // Sort exercises by startY ascending (top to bottom on page)
                    // Cloud analysis returns normalized coordinates where lower startY = higher on page (top to bottom reading order)
                    ForEach(analysis.exercises.sorted { $0.startY < $1.startY }, id: \.self) { exercise in
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

struct ExerciseCard: View {
    let exercise: AIAnalysisService.Exercise
    @ObservedObject var homeworkItem: Item

    var body: some View {
        ExerciseCardContent(
            exercise: exercise,
            imageData: homeworkItem.imageData,
            exerciseAnswers: Binding(
                get: { homeworkItem.exerciseAnswers },
                set: { newValue in
                    homeworkItem.exerciseAnswers = newValue
                    if let context = homeworkItem.managedObjectContext {
                        try? context.save()
                    }
                }
            )
        )
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
