//
//  AssignmentDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import PencilKit

/// View for displaying and analyzing a Google Classroom assignment
struct AssignmentDetailView: View {
    @StateObject var assignment: ClassroomAssignment
    @State private var isAnalyzing = false
    @State private var isReanalyzing = false
    @State private var analysisError: String?
    @State private var analysisProgress: (current: Int, total: Int)?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var didTriggerAutoAnalysis = false

    var body: some View {
        VStack(spacing: 0) {
            if isAnalyzing || assignment.isDownloadingImage {
                // Show progress indicator during download or analysis
                VStack(spacing: 16) {
                    Spacer()

                    if assignment.isDownloadingImage {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Downloading image...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    } else if let progress = analysisProgress {
                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 300)
                        Text("Analyzing segment \(progress.current) of \(progress.total)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Analyzing assignment...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }

                    Spacer()
                }
            } else if let analysis = assignment.analysisResult, !analysis.exercises.isEmpty {
                // Show exercises directly
                VStack(spacing: 0) {
                    // Action buttons at the top
                    HStack(spacing: 12) {
                        // View Original button - show image or text
                        if assignment.imageData != nil {
                            // Has image - show image viewer
                            NavigationLink(destination: AssignmentImageView(assignment: assignment)) {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.fill")
                                        .font(.title2)
                                    Text("View Original")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        } else if assignment.extractedText != nil || assignment.coursework.description != nil {
                            // No image but has text - show text viewer
                            NavigationLink(destination: AssignmentTextView(assignment: assignment)) {
                                VStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.title2)
                                    Text("View Original")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }

                        // Analyze with Apple Intelligence button - always show
                        if !isAnalyzing {
                            Button(action: {
                                isReanalyzing = true
                                if assignment.imageData != nil {
                                    analyzeAssignment(useCloud: false)
                                } else if let text = assignment.extractedText {
                                    analyzeTextOnly(text: text)
                                }
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "apple.logo")
                                        .font(.title2)
                                    Text("Apple AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || assignment.isDownloadingImage)
                        }

                        // Analyze with Google Gemini button - show when cloud analysis is enabled
                        if useCloudAnalysis && !isAnalyzing {
                            Button(action: {
                                isReanalyzing = true
                                if assignment.imageData != nil {
                                    analyzeAssignment(useCloud: true)
                                }
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "cloud.fill")
                                        .font(.title2)
                                    Text("Google AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || assignment.isDownloadingImage || assignment.imageData == nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    // Exercises content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Summary card
                            SummaryCard(
                                icon: "pencil.circle.fill",
                                title: "Exercises",
                                count: analysis.exercises.count,
                                color: .green
                            )
                            .padding(.horizontal)

                            // Exercises
                            Text("✏️ Exercises")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            ForEach(analysis.exercises, id: \.self) { exercise in
                                ClassroomExerciseCard(exercise: exercise, assignment: assignment)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .id(assignment.analysisJSON ?? "")
                }
            } else {
                // No analysis exists - show original content and analyze options
                VStack(spacing: 0) {
                    // Action buttons at the top
                    HStack(spacing: 12) {
                        // Analyze with Apple Intelligence button
                        Button(action: {
                            if let _ = assignment.imageData {
                                analyzeAssignment(useCloud: false)
                            } else if let text = assignment.extractedText {
                                analyzeTextOnly(text: text)
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "apple.logo")
                                    .font(.title2)
                                Text("Apple AI")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .cornerRadius(10)
                        }
                        .disabled(isAnalyzing || assignment.isDownloadingImage)

                        // Analyze with Google Gemini button
                        if useCloudAnalysis {
                            Button(action: {
                                if assignment.imageData != nil {
                                    analyzeAssignment(useCloud: true)
                                }
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "cloud.fill")
                                        .font(.title2)
                                    Text("Google AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            .disabled(isAnalyzing || assignment.isDownloadingImage || assignment.imageData == nil)
                        }
                        
                        // Download and Analyze button
                        if assignment.imageData == nil && assignment.firstImageMaterial != nil {
                            Button(action: downloadAndAnalyze) {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                    Text("Download & Analyze")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .disabled(isAnalyzing || assignment.isDownloadingImage)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    // Original content
                    if assignment.imageData != nil {
                        AssignmentImageView(assignment: assignment)
                    } else {
                        AssignmentTextView(assignment: assignment)
                    }
                }
            }
        }
        .navigationTitle("Exercises")
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
        }
        .onChange(of: isAnalyzing) { _, newValue in
            if !newValue {
                isReanalyzing = false
            }
        }
        .onAppear {
            guard !didTriggerAutoAnalysis else { return }
            didTriggerAutoAnalysis = true

            if isAnalyzing || assignment.isDownloadingImage {
                return
            }

            if assignment.analysisResult == nil || assignment.analysisResult?.exercises.isEmpty == true {
                if assignment.imageData != nil {
                    analyzeAssignment()
                } else if assignment.firstImageMaterial != nil {
                    downloadAndAnalyze()
                } else if let description = assignment.coursework.description, !description.isEmpty {
                    analyzeTextOnly(text: description)
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
        // Check if we're overwriting existing analysis
        if let oldAnalysis = assignment.analysisResult {
            print("DEBUG SAVE: ⚠️ OVERWRITING existing classroom assignment analysis")
            print("DEBUG SAVE: Previous analysis had \(oldAnalysis.exercises.count) exercises")
        } else {
            print("DEBUG SAVE: Creating new analysis for classroom assignment")
        }

        do {
            print("DEBUG SAVE: Saving analysis - Exercises: \(analysis.exercises.count)")
            print("DEBUG SAVE: Exercise order before encoding:")
            for (idx, ex) in analysis.exercises.enumerated() {
                print("  Position \(idx): Exercise #\(ex.exerciseNumber), Y: \(ex.startY)-\(ex.endY)")
                print("     Content preview: \(ex.fullContent.prefix(80))...")
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(analysis)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Explicitly overwrite analysisJSON field
                assignment.analysisJSON = jsonString
                assignment.saveToCache()
                print("DEBUG SAVE: ✅ Analysis saved to UserDefaults (overwrites any previous analysis)")
            }
        } catch {
            print("❌ Error encoding analysis: \(error)")
        }
    }

    // MARK: - Text Analysis

    /// Analyze text-only assignment using AI (no image available)
    private func analyzeTextOnly(text: String) {
        isAnalyzing = true
        analysisError = nil

        // Store the original text as extractedText
        assignment.extractedText = text

        print("🔍 Starting AI text analysis...")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                isAnalyzing = false

                switch result {
                case .success(let analysis):
                    print("✅ Text analysis complete - Found \(analysis.exercises.count) exercises")
                    saveAnalysisResult(analysis)

                case .failure(let error):
                    print("❌ Text analysis failed: \(error.localizedDescription)")
                    analysisError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Supporting Views

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

/// A simple view to display the assignment image
private struct AssignmentImageView: View {
    @ObservedObject var assignment: ClassroomAssignment

    var body: some View {
        ScrollView {
            if let imageData = assignment.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Image")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Image")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A simple view to display the assignment original text
private struct AssignmentTextView: View {
    @ObservedObject var assignment: ClassroomAssignment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Show assignment description if available
                if let description = assignment.coursework.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Text Available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Original")
        .navigationBarTitleDisplayMode(.inline)
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
