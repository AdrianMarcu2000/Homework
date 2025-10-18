
//
//  ExerciseCardContent.swift
//  Homework
//
//  Created by Gemini on 12.10.2025.
//

import SwiftUI
import LaTeXSwiftUI
import PencilKit
import CoreData

/// Reusable exercise card content
struct ExerciseCardContent: View {
    let exercise: AIAnalysisService.Exercise
    let imageData: Data?
    @Binding var exerciseAnswers: [String: Data]?
    @State private var similarExercises: [AIAnalysisService.SimilarExercise] = []
    @State private var isLoadingSimilarExercises = false
    @State private var similarExercisesErrorMessage: String?
    @State private var hints: [AIAnalysisService.Hint] = []
    @State private var revealedHintIndex: Int = -1
    @State private var isLoadingHints = false
    @State private var hintsErrorMessage: String?
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
        let isMath = exercise.subject == "mathematics"
        
        // Canvas for showing work - use math notebook style for math
        if isMath {
            MathNotebookCanvasView(exercise: exercise, imageData: imageData, exerciseAnswers: $exerciseAnswers, canvasData: $canvasData)
        } else {
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
                
                /* This code has been removed to simplify the UI
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
                 */
                
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
            
            LaTeX(exercise.fullContent)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(.primary)
                .onAppear {
                    print("🖥️ UI RENDER: Displaying exercise #\(exercise.exerciseNumber)")
                    print("DEBUG LATEX: \(exercise.fullContent)")
                    if exercise.fullContent.count > 150 {
                        print("   (total length: \(exercise.fullContent.count) chars)")
                    }
                }
            
            // Hints Section
            HintsSectionView(hints: $hints, revealedHintIndex: $revealedHintIndex, isLoading: $isLoadingHints, errorMessage: $hintsErrorMessage, onGenerate: generateHints)
            
            // Action buttons (hints)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: {
                        if hints.isEmpty && !isLoadingHints {
                            generateHints()
                        } else if !hints.isEmpty {
                            revealNextHint()
                        }
                    }) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                            Text(hints.isEmpty ? "Get Hints" : (revealedHintIndex < hints.count - 1 ? "Next Hint" : "All Hints Shown"))
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
                    .disabled(isLoadingHints || (revealedHintIndex >= hints.count - 1 && !hints.isEmpty))
                }
            }
            
            // Answer input area based on inputType
            Divider()
                .padding(.vertical, 4)
            
            answerInputView
            
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
            
            // Practice button
            Button(action: {
                if similarExercises.isEmpty && !isLoadingSimilarExercises {
                    generateSimilarExercises()
                }
            }) {
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
            .disabled(isLoadingSimilarExercises)
            
            // Similar Exercises Section
            SimilarExercisesSectionView(similarExercises: $similarExercises, isLoading: $isLoadingSimilarExercises, errorMessage: $similarExercisesErrorMessage, originalExercise: exercise, onGenerate: generateSimilarExercises)
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        
        .sheet(isPresented: $showVerificationResult) {
            if let result = verificationResult {
                VerificationResultView(result: result)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateHints() {
        isLoadingHints = true
        hintsErrorMessage = nil
        
        // Check if Apple Intelligence is available
        let isAppleIntelligenceAvailable = AIAnalysisService.shared.isModelAvailable
        
        // Use cloud service if Apple Intelligence is not available OR if cloud analysis is enabled
        if !isAppleIntelligenceAvailable || useCloudAnalysis {
            print("DEBUG HINTS: Using cloud service for hints generation (AI available: \(isAppleIntelligenceAvailable), cloud enabled: \(useCloudAnalysis))")
            CloudAnalysisService.shared.generateHints(for: exercise) { result in
                DispatchQueue.main.async {
                    self.isLoadingHints = false
                    
                    switch result {
                    case .success(let generatedHints):
                        self.hints = generatedHints.sorted { $0.level < $1.level }
                        self.revealNextHint()
                    case .failure(let error):
                        self.hintsErrorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            print("DEBUG HINTS: Using Apple Intelligence for hints generation")
            AIAnalysisService.shared.generateHints(for: exercise) { result in
                DispatchQueue.main.async {
                    self.isLoadingHints = false
                    
                    switch result {
                    case .success(let generatedHints):
                        self.hints = generatedHints.sorted { $0.level < $1.level }
                        self.revealNextHint()
                    case .failure(let error):
                        self.hintsErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    private func revealNextHint() {
        withAnimation {
            if revealedHintIndex < hints.count - 1 {
                revealedHintIndex += 1
            }
        }
    }
    
    private func generateSimilarExercises() {
        isLoadingSimilarExercises = true
        similarExercisesErrorMessage = nil
        
        // Check if Apple Intelligence is available
        let isAppleIntelligenceAvailable = AIAnalysisService.shared.isModelAvailable
        
        // Use cloud service if Apple Intelligence is not available OR if cloud analysis is enabled
        if !isAppleIntelligenceAvailable || useCloudAnalysis {
            print("DEBUG SIMILAR: Using cloud service for similar exercises generation (AI available: \(isAppleIntelligenceAvailable), cloud enabled: \(useCloudAnalysis))")
            CloudAnalysisService.shared.generateSimilarExercises(
                basedOn: exercise,
                count: 3
            ) { result in
                DispatchQueue.main.async {
                    self.isLoadingSimilarExercises = false
                    
                    switch result {
                    case .success(let exercises):
                        self.similarExercises = exercises
                    case .failure(let error):
                        self.similarExercisesErrorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            print("DEBUG SIMILAR: Using Apple Intelligence for similar exercises generation")
            AIAnalysisService.shared.generateSimilarExercises(
                basedOn: exercise,
                count: 3
            ) { result in
                DispatchQueue.main.async {
                    self.isLoadingSimilarExercises = false
                    
                    switch result {
                    case .success(let exercises):
                        self.similarExercises = exercises
                    case .failure(let error):
                        self.similarExercisesErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    /// Verifies the student's answer using cloud AI
    private func verifyAnswer() {
        isVerifying = true
        
        var canvasDrawing: PKDrawing?
        
        // Get canvas drawing
        if let savedData = canvasData,
           let drawing = try? PKDrawing(data: savedData) {
            canvasDrawing = drawing
        }
        
        // Validate we have an answer
        guard canvasDrawing != nil else {
            isVerifying = false
            print("DEBUG VERIFY: No answer found for exercise \(exercise.exerciseNumber)")
            return
        }
        
        print("DEBUG VERIFY: Verifying answer - Type: canvas, Has canvas: \(canvasDrawing != nil)")
        
        // Call verification service
        AnswerVerificationService.shared.verifyAnswer(
            exercise: exercise,
            answerType: "canvas",
            answerText: nil,
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
}

private struct SimilarExercisesSectionView: View {
    @Binding var similarExercises: [AIAnalysisService.SimilarExercise]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let originalExercise: AIAnalysisService.Exercise
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Generating similar exercises...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error loading similar exercises")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Try Again", action: onGenerate)
                        .buttonStyle(.bordered)
                }
            } else if !similarExercises.isEmpty {
                Text("Similar Exercises")
                    .font(.headline)
                    .foregroundColor(.secondary)
                CombinedSimilarExercisesCard(exercises: similarExercises, originalExercise: originalExercise)
            }
        }
        .padding(.top, 8)
    }
}

private struct CombinedSimilarExercisesCard: View {
    let exercises: [AIAnalysisService.SimilarExercise]
    let originalExercise: AIAnalysisService.Exercise
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(exercises) { exercise in
                PracticeExerciseCard(
                    practiceExercise: exercise,
                    originalExercise: originalExercise,
                    useCloudAnalysis: useCloudAnalysis
                )

                if exercise.id != exercises.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func difficultyColor(for difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easier": return .green
        case "harder": return .red
        default: return .orange
        }
    }
    
    private func difficultyIcon(for difficulty: String) -> some View {
        Group {
            switch difficulty.lowercased() {
            case "easier":
                Image(systemName: "arrow.down.circle.fill")
            case "harder":
                Image(systemName: "arrow.up.circle.fill")
            default:
                Image(systemName: "equal.circle.fill")
            }
        }
        .foregroundColor(difficultyColor(for: difficulty))
        .font(.caption)
    }
}

private struct HintsSectionView: View {
    @Binding var hints: [AIAnalysisService.Hint]
    @Binding var revealedHintIndex: Int
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onGenerate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Generating hints...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error loading hints")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Try Again", action: onGenerate)
                        .buttonStyle(.bordered)
                }
            } else if !hints.isEmpty {
                Text("Hints")
                    .font(.headline)
                    .foregroundColor(.secondary)
                if revealedHintIndex >= 0 {
                    ForEach(0...revealedHintIndex, id: \.self) { index in
                        if index < hints.count {
                            HintCard(hint: hints[index])
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

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
                LaTeX(hint.content)
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

private struct PracticeExerciseCard: View {
    let practiceExercise: AIAnalysisService.SimilarExercise
    let originalExercise: AIAnalysisService.Exercise
    let useCloudAnalysis: Bool

    @State private var canvasData: Data?
    @State private var isVerifying = false
    @State private var verificationResult: VerificationResult?
    @State private var showVerificationResult = false

    private var isMath: Bool {
        originalExercise.subject == "mathematics"
    }

    private func difficultyColor(for difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "easier": return .green
        case "harder": return .red
        default: return .orange
        }
    }

    private func difficultyIcon(for difficulty: String) -> some View {
        Group {
            switch difficulty.lowercased() {
            case "easier":
                Image(systemName: "arrow.down.circle.fill")
            case "harder":
                Image(systemName: "arrow.up.circle.fill")
            default:
                Image(systemName: "equal.circle.fill")
            }
        }
        .foregroundColor(difficultyColor(for: difficulty))
        .font(.caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    difficultyIcon(for: practiceExercise.difficulty)
                    Text(practiceExercise.difficulty.capitalized)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(difficultyColor(for: practiceExercise.difficulty).opacity(0.2))
                .cornerRadius(8)
            }

            LaTeX(practiceExercise.content)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(.primary)

            // Answer input area
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Answer:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isMath {
                    PracticeCanvasView(canvasData: $canvasData, isMath: true)
                } else {
                    PracticeCanvasView(canvasData: $canvasData, isMath: false)
                }
            }

            // Verify button (only show if cloud analysis is enabled)
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
                            Text("Verify Answer")
                        }
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isVerifying)
            }
        }
        .sheet(isPresented: $showVerificationResult) {
            if let result = verificationResult {
                VerificationResultView(result: result)
            }
        }
    }

    private func verifyAnswer() {
        isVerifying = true

        var canvasDrawing: PKDrawing?

        // Get canvas drawing
        if let savedData = canvasData,
           let drawing = try? PKDrawing(data: savedData) {
            canvasDrawing = drawing
        }

        // Validate we have an answer
        guard canvasDrawing != nil else {
            isVerifying = false
            print("DEBUG VERIFY: No answer found for practice exercise")
            return
        }

        // Create a temporary exercise from the practice exercise for verification
        let tempExercise = AIAnalysisService.Exercise(
            exerciseNumber: practiceExercise.exerciseNumber,
            type: practiceExercise.type,
            fullContent: practiceExercise.content,
            startY: 0.0,
            endY: 0.0,
            subject: originalExercise.subject,
            inputType: originalExercise.inputType
        )

        print("DEBUG VERIFY: Verifying practice answer - Type: canvas, Has canvas: \(canvasDrawing != nil)")

        // Call verification service
        AnswerVerificationService.shared.verifyAnswer(
            exercise: tempExercise,
            answerType: "canvas",
            answerText: nil,
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
}

private struct PracticeCanvasView: View {
    @Binding var canvasData: Data?
    let isMath: Bool
    @State private var canvas = PKCanvasView()

    var body: some View {
        CanvasViewRepresentable(canvasView: canvas, canvasData: $canvasData, isMath: isMath)
            .frame(height: 200)
            .background(isMath ? Color(red: 1.0, green: 0.98, blue: 0.94) : Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct CanvasViewRepresentable: UIViewRepresentable {
    let canvasView: PKCanvasView
    @Binding var canvasData: Data?
    let isMath: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = isMath ? UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0) : .white
        canvasView.isOpaque = false

        // Load existing drawing if available
        if let data = canvasData,
           let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }

        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasData: $canvasData)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var canvasData: Data?

        init(canvasData: Binding<Data?>) {
            _canvasData = canvasData
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            canvasData = canvasView.drawing.dataRepresentation()
        }
    }
}
