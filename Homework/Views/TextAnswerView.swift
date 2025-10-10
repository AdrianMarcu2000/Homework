//
//  TextAnswerView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import CoreData

/// A text input view for answering exercises with typed responses
struct TextAnswerView: View {
    let exercise: AIAnalysisService.Exercise
    let homeworkItem: Item

    @State private var answerText: String = ""
    @FocusState private var isFocused: Bool

    init(exercise: AIAnalysisService.Exercise, homeworkItem: Item) {
        self.exercise = exercise
        self.homeworkItem = homeworkItem

        // Load existing answer if available
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_text"
        if let answers = homeworkItem.exerciseAnswers,
           let savedData = answers[key],
           let savedText = String(data: savedData, encoding: .utf8) {
            _answerText = State(initialValue: savedText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.cursor")
                    .foregroundColor(.green)
                Text("Your Answer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Spacer()
                if !answerText.isEmpty {
                    Button(action: clearAnswer) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Text input area
            TextEditor(text: $answerText)
                .font(.body)
                .padding(12)
                .frame(minHeight: 100)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.green : Color.gray.opacity(0.3), lineWidth: isFocused ? 2 : 1)
                )
                .focused($isFocused)
                .onChange(of: answerText) { _, newValue in
                    saveAnswer(newValue)
                }

            // Placeholder text when empty
            if answerText.isEmpty && !isFocused {
                Text("Tap to type your answer...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, -88)
                    .allowsHitTesting(false)
            }

            // Character count (optional)
            if !answerText.isEmpty {
                Text("\(answerText.count) characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func clearAnswer() {
        answerText = ""
        saveAnswer("")
    }

    private func saveAnswer(_ text: String) {
        guard let context = homeworkItem.managedObjectContext else { return }

        context.perform {
            // Get or create exercise answers dictionary
            var answers = homeworkItem.exerciseAnswers ?? [:]

            // Store the text answer for this exercise (convert to Data)
            let key = "\(exercise.exerciseNumber)_\(exercise.startY)_text"
            if text.isEmpty {
                answers.removeValue(forKey: key)
            } else {
                // Convert string to Data for storage
                if let textData = text.data(using: .utf8) {
                    answers[key] = textData
                }
            }

            // Save back to Core Data
            homeworkItem.exerciseAnswers = answers

            do {
                try context.save()
            } catch {
                print("Error saving text answer: \(error)")
            }
        }
    }
}

#Preview {
    let mockExercise = AIAnalysisService.Exercise(
        exerciseNumber: "1",
        type: "short_answer",
        fullContent: "What is the capital of France?",
        startY: 0.3,
        endY: 0.35,
        subject: "history",
        inputType: "text"
    )

    let mockItem: Item = {
        let context = PersistenceController.preview.container.viewContext
        let item = Item(context: context)
        item.timestamp = Date()
        return item
    }()

    return TextAnswerView(
        exercise: mockExercise,
        homeworkItem: mockItem
    )
    .padding()
}
