
//
//  ExerciseCardContent.swift
//  Homework
//
//  Created by Gemini on 12.10.2025.
//

import SwiftUI
import PencilKit
import CoreData

/// Reusable exercise card content
struct ExerciseCardContent: View {
    let exercise: AIAnalysisService.Exercise
    let imageData: Data?
    @Binding var exerciseAnswers: [String: Data]?
    @State private var showSimilarExercises = false
    @State private var showHints = false
    @State private var canvasData: Data?
    @State private var isVerifying = false
    @State private var verificationResult: VerificationResult?
    @State private var showVerificationResult = false
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    private var croppedExerciseImage: UIImage? {
        guard let imageData = imageData,
              let fullImage = UIImage(data: imageData) else {
            return nil
        }
        return fullImage.crop(startY: exercise.startY, endY: exercise.endY, padding: 0.03)
    }

    init(exercise: AIAnalysisService.Exercise, imageData: Data?, exerciseAnswers: Binding<[String: Data]?>) {
        self.exercise = exercise
        self.imageData = imageData
        self._exerciseAnswers = exerciseAnswers

        let key = "\(exercise.exerciseNumber)_\(exercise.startY)"
        _canvasData = State(initialValue: exerciseAnswers.wrappedValue?[key])
    }

    /// Computed view that returns the appropriate input method based on exercise type
    @ViewBuilder
    private var answerInputView: some View {
        let inputType = exercise.inputType ?? "canvas" // default to canvas if not specified
        let isMath = exercise.subject == "mathematics"

        switch inputType {
        case "inline":
            // Inline fill-in-the-blank input
            InlineAnswerView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers)

        case "text":
            // Simple text input for short answers
            TextAnswerView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers)

        case "canvas":
            // Canvas for showing work - use math notebook style for math
            if isMath {
                MathNotebookCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
            } else {
                DrawingCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
            }

        case "both":
            // Both canvas and text input
            VStack(spacing: 12) {
                if isMath {
                    MathNotebookCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
                } else {
                    DrawingCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
                }
                TextAnswerView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers)
            }

        default:
            // Fallback to canvas
            DrawingCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Reuse the same design as homework exercises
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
                .onAppear {
                    print("🖥️ UI RENDER: Displaying exercise #\(exercise.exerciseNumber)")
                    print("   Content: \(exercise.fullContent.prefix(150))...")
                    if exercise.fullContent.count > 150 {
                        print("   (total length: \(exercise.fullContent.count) chars)")
                    }
                }

            // Action buttons (hints and practice)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
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
                        .background(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

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
                        .background(LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Verify Answer button (only show if cloud analysis is enabled)
                if useCloudAnalysis {
                    Button(action: verifyAnswer) {
                        HStack {
                            if isVerifying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Verifying...")
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                Text("Verify my answer")
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isVerifying)
                }
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
        .sheet(isPresented: $showVerificationResult) {
            if let result = verificationResult {
                VerificationResultView(result: result)
            }
        }
    }

    // MARK: - Helper Functions

    /// Verifies the student's answer using cloud AI
    private func verifyAnswer() {
        isVerifying = true

        // Determine the answer type and extract the answer
        let inputType = exercise.inputType ?? "canvas"
        var answerText: String?
        var canvasDrawing: PKDrawing?

        // Extract answer based on input type
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)"

        switch inputType {
        case "inline":
            // Get inline answer
            let inlineKey = "\(key)_inline"
            if let answers = exerciseAnswers,
               let savedData = answers[inlineKey],
               let text = String(data: savedData, encoding: .utf8), !text.isEmpty {
                answerText = text
            }

        case "text":
            // Get text answer
            let textKey = "\(key)_text"
            if let answers = exerciseAnswers,
               let savedData = answers[textKey],
               let text = String(data: savedData, encoding: .utf8), !text.isEmpty {
                answerText = text
            }

        case "canvas":
            // Get canvas drawing
            if let savedData = canvasData,
               let drawing = try? PKDrawing(data: savedData) {
                canvasDrawing = drawing
            }

        case "both":
            // Get both canvas and text
            if let savedData = canvasData,
               let drawing = try? PKDrawing(data: savedData) {
                canvasDrawing = drawing
            }
            let textKey = "\(key)_text"
            if let answers = exerciseAnswers,
               let savedData = answers[textKey],
               let text = String(data: savedData, encoding: .utf8), !text.isEmpty {
                answerText = text
            }

        default:
            // Default to canvas
            if let savedData = canvasData,
               let drawing = try? PKDrawing(data: savedData) {
                canvasDrawing = drawing
            }
        }

        // Validate we have an answer
        guard answerText != nil || canvasDrawing != nil else {
            isVerifying = false
            print("DEBUG VERIFY: No answer found for exercise \(exercise.exerciseNumber)")
            return
        }

        // Determine verification type (prefer canvas if available for "both")
        let verificationType: String
        if canvasDrawing != nil {
            verificationType = "canvas"
        } else {
            verificationType = inputType == "inline" ? "inline" : "text"
        }

        print("DEBUG VERIFY: Verifying answer - Type: \(verificationType), Has text: \(answerText != nil), Has canvas: \(canvasDrawing != nil)")

        // Call verification service
        AnswerVerificationService.shared.verifyAnswer(
            exercise: exercise,
            answerType: verificationType,
            answerText: answerText,
            canvasDrawing: canvasDrawing
        ) { [self] result in
            DispatchQueue.main.async {
                self.isVerifying = false

                switch result {
                case .success(let verificationResult):
                    print("DEBUG VERIFY: Success - Correct: \(verificationResult.isCorrect)")
                    self.verificationResult = verificationResult
                    self.showVerificationResult = true

                case .failure(let error):
                    print("DEBUG VERIFY: Failed - \(error.localizedDescription)")
                }
            }
        }
    }

    private func inputTypeIcon(_ inputType: String) -> String {
        switch inputType {
        case "inline": return "pencil.line"
        case "text": return "text.cursor"
        case "canvas": return "pencil.tip"
        case "both": return "square.split.2x1"
        default: return "questionmark"
        }
    }

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
