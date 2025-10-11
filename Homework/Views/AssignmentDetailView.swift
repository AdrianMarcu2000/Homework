//
//  AssignmentDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData

/// View for displaying and analyzing a Google Classroom assignment
struct AssignmentDetailView: View {
    @StateObject var assignment: ClassroomAssignment
    @State private var selectedTab = 0
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var analysisProgress: (current: Int, total: Int)?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Custom tab buttons
            HStack(spacing: 0) {
                TabButton(title: "Image", icon: "photo", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Exercises", icon: "pencil.circle.fill", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground))

            // Tab content
            TabView(selection: $selectedTab) {
                // Image Tab
                Group {
                    if assignment.isDownloadingImage {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Downloading image...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let imageData = assignment.imageData,
                              let uiImage = UIImage(data: imageData) {
                        ScrollView {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding()
                        }
                    } else if assignment.firstImageMaterial != nil {
                        // Has image but not downloaded yet
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.blue)

                            Text("Image available")
                                .font(.headline)

                            Button(action: downloadAndAnalyze) {
                                Text("Download & Analyze")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: 200)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Image Attachment")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(assignment.coursework.description ?? "")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                }
                .tag(0)

                // Exercises Tab
                Group {
                    if isAnalyzing {
                        VStack(spacing: 16) {
                            if let progress = analysisProgress {
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 300)
                                Text("Analyzing segment \(progress.current) of \(progress.total)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ProgressView()
                                Text("Analyzing assignment...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if let analysis = assignment.analysisResult, !analysis.exercises.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("✏️ Exercises")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                ForEach(Array(analysis.exercises.enumerated()), id: \.offset) { index, exercise in
                                    ClassroomExerciseCard(exercise: exercise, assignment: assignment)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Exercises")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            if assignment.imageData != nil && assignment.analysisJSON == nil {
                                Button(action: { analyzeAssignment() }) {
                                    Text("Analyze Image")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: 200)
                                        .background(Color.green)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(assignment.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(assignment.courseName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if assignment.imageData != nil {
                    Menu {
                        Button(action: { analyzeAssignment(useCloud: false) }) {
                            Label("Re-analyze (Local)", systemImage: "arrow.clockwise")
                        }

                        if useCloudAnalysis {
                            Button(action: { analyzeAssignment(useCloud: true) }) {
                                Label("Re-analyze (Cloud)", systemImage: "cloud")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .disabled(isAnalyzing)
                }
            }
        }
    }

    // MARK: - Actions

    private func downloadAndAnalyze() {
        Task {
            do {
                try await assignment.downloadImage()
                analyzeAssignment()
            } catch {
                analysisError = error.localizedDescription
                print("❌ Failed to download image: \(error)")
            }
        }
    }

    private func analyzeAssignment(useCloud: Bool = false) {
        guard let imageData = assignment.imageData,
              let image = UIImage(data: imageData) else {
            return
        }

        isAnalyzing = true
        analysisError = nil
        analysisProgress = nil

        // Step 1: Perform OCR
        OCRService.shared.recognizeTextWithBlocks(from: image) { result in
            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    assignment.extractedText = ocrResult.fullText
                }

                // Step 2: Analyze with AI
                if useCloud {
                    analyzeWithCloud(image: image, ocrBlocks: ocrResult.blocks)
                } else {
                    analyzeWithLocal(image: image, ocrBlocks: ocrResult.blocks)
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    isAnalyzing = false
                    analysisError = error.localizedDescription
                    print("❌ OCR failed: \(error)")
                }
            }
        }
    }

    private func analyzeWithLocal(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
        let aiBlocks = ocrBlocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: aiBlocks,
            progressHandler: { current, total in
                DispatchQueue.main.async {
                    analysisProgress = (current, total)
                }
            }
        ) { result in
            DispatchQueue.main.async {
                isAnalyzing = false
                analysisProgress = nil

                switch result {
                case .success(let analysis):
                    saveAnalysisResult(analysis)

                case .failure(let error):
                    analysisError = error.localizedDescription
                    print("❌ Analysis failed: \(error)")
                }
            }
        }
    }

    private func analyzeWithCloud(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
        let aiBlocks = ocrBlocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

        CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: aiBlocks) { result in
            DispatchQueue.main.async {
                isAnalyzing = false

                switch result {
                case .success(let analysis):
                    saveAnalysisResult(analysis)

                case .failure(let error):
                    analysisError = error.localizedDescription
                    print("❌ Cloud analysis failed: \(error)")
                }
            }
        }
    }

    private func saveAnalysisResult(_ analysis: AIAnalysisService.AnalysisResult) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(analysis)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                assignment.analysisJSON = jsonString
                assignment.saveToCache()
                print("✅ Analysis saved for classroom assignment")
            }
        } catch {
            print("❌ Error encoding analysis: \(error)")
        }
    }
}

/// Exercise card for classroom assignments
private struct ClassroomExerciseCard: View {
    let exercise: AIAnalysisService.Exercise
    @ObservedObject var assignment: ClassroomAssignment

    var body: some View {
        ExerciseCardContent(
            exercise: exercise,
            imageData: assignment.imageData,
            exerciseAnswers: Binding(
                get: { assignment.exerciseAnswers },
                set: { assignment.exerciseAnswers = $0; assignment.saveToCache() }
            )
        )
    }
}

/// Reusable exercise card content
private struct ExerciseCardContent: View {
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

            // Action buttons (hints and practice)
            HStack(spacing: 8) {
                Button(action: { showHints = true }) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                        Text("Hint")
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

            // Note: Answer input is read-only for classroom assignments (no saving to classroom)
            Text("Note: This is a Google Classroom assignment. Answers are stored locally and not submitted to Classroom.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
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

/// Custom tab button (reused from HomeworkListView)
private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    let mockCoursework = ClassroomCoursework(
        id: "1",
        courseId: "course1",
        title: "Math Homework - Chapter 5",
        description: "Complete exercises 1-10 from Chapter 5",
        materials: nil,
        state: "PUBLISHED",
        creationTime: "2025-10-11T10:00:00Z",
        updateTime: nil,
        dueDate: nil,
        maxPoints: 100,
        workType: "ASSIGNMENT",
        alternateLink: nil
    )

    NavigationView {
        AssignmentDetailView(assignment: ClassroomAssignment(coursework: mockCoursework, courseName: "Mathematics"))
    }
}
