//
//  InlineAnswerView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import CoreData

/// A compact inline text input for fill-in-the-blank exercises
struct InlineAnswerView: View {
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: (any AnalyzableHomework)?
    @Binding var exerciseAnswers: [String: Data]?

    @State private var answerText: String = ""
    @FocusState private var isFocused: Bool

    // Convenience init for Item (backward compatibility)
    init(exercise: AIAnalysisService.Exercise, homeworkItem: Item) {
        self.exercise = exercise
        self.homeworkItem = homeworkItem

        // Create a binding that reads from and writes to Item's exerciseAnswers
        self._exerciseAnswers = Binding(
            get: { homeworkItem.exerciseAnswers },
            set: { newValue in
                homeworkItem.exerciseAnswers = newValue
                if let context = homeworkItem.managedObjectContext {
                    try? context.save()
                }
            }
        )

        // Load existing answer
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_inline"
        if let answers = homeworkItem.exerciseAnswers,
           let savedData = answers[key],
           let text = String(data: savedData, encoding: .utf8) {
            _answerText = State(initialValue: text)
        }
    }

    // Generic init for any AnalyzableHomework (including ClassroomAssignment)
    init(exercise: AIAnalysisService.Exercise, imageData: Data?, exerciseAnswers: Binding<[String: Data]?>) {
        self.exercise = exercise
        self.homeworkItem = nil
        self._exerciseAnswers = exerciseAnswers

        // Load existing answer if available
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_inline"
        if let answers = exerciseAnswers.wrappedValue,
           let savedData = answers[key],
           let savedText = String(data: savedData, encoding: .utf8) {
            _answerText = State(initialValue: savedText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pencil.line")
                    .foregroundColor(.orange)
                Text("Fill in your answer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                Spacer()
                if !answerText.isEmpty {
                    Button(action: clearAnswer) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Compact text field for inline answer
            HStack {
                Text("Answer:")
                    .font(.body)
                    .foregroundColor(.secondary)

                TextField("Type here...", text: $answerText)
                    .font(.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isFocused ? Color.orange : Color.gray.opacity(0.3), lineWidth: isFocused ? 2 : 1)
                    )
                    .focused($isFocused)
                    .onChange(of: answerText) { _, newValue in
                        saveAnswer(newValue)
                    }
            }

            // Show placeholder hint if empty
            if answerText.isEmpty && !isFocused {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                    Text("Look for blanks (___) or fill-in spaces in the exercise above")
                        .font(.caption2)
                }
                .foregroundColor(.orange.opacity(0.7))
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func clearAnswer() {
        answerText = ""
        saveAnswer("")
    }

    private func saveAnswer(_ text: String) {
        // Get or create exercise answers dictionary
        var answers = exerciseAnswers ?? [:]

        // Store the inline answer for this exercise (convert to Data)
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_inline"
        if text.isEmpty {
            answers.removeValue(forKey: key)
        } else {
            // Convert string to Data for storage
            if let textData = text.data(using: .utf8) {
                answers[key] = textData
            }
        }

        // Update the binding (which will trigger save in the parent)
        exerciseAnswers = answers
    }
}

#Preview {
    let mockExercise = AIAnalysisService.Exercise(
        exerciseNumber: "1",
        type: "fill_in_blanks",
        fullContent: "The capital of France is ___.",
        startY: 0.3,
        endY: 0.35,
        subject: "geography",
        inputType: "inline"
    )

    let mockItem: Item = {
        let context = PersistenceController.preview.container.viewContext
        let item = Item(context: context)
        item.timestamp = Date()
        return item
    }()

    return InlineAnswerView(
        exercise: mockExercise,
        homeworkItem: mockItem
    )
    .padding()
}
