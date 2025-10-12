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
    @State private var selectedTab = 0
    @State private var isAnalyzing = false
    @State private var isReanalyzing = false
    @State private var analysisError: String?
    @State private var analysisProgress: (current: Int, total: Int)?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var didTriggerAutoAnalysis = false

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
                            Spacer()

                            if let progress = analysisProgress {
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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("✏️ Exercises")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                ForEach(analysis.exercises, id: \.exerciseNumber) { exercise in
                                    ClassroomExerciseCard(exercise: exercise, assignment: assignment)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                        .id(assignment.analysisJSON ?? "")
                    } else {
                        // No analysis exists - show analyze options
                        VStack(spacing: 20) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Analysis Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            // Show appropriate analyze button based on what's available
                            if assignment.imageData != nil {
                                // Has image - offer image analysis
                                Button(action: { analyzeAssignment() }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.magnifyingglass")
                                            .font(.title2)
                                        Text("Analyze Image")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: 200)
                                    .background(Color.green)
                                    .cornerRadius(10)
                                }
                            } else if let description = assignment.coursework.description, !description.isEmpty {
                                // No image but has text - offer text analysis
                                Button(action: { analyzeTextOnly(text: description) }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "text.magnifyingglass")
                                            .font(.title2)
                                        Text("Analyze Text")
                                            .font(.headline)
                                        Text("Extract exercises from description")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: 250)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                }
                            } else if assignment.firstImageMaterial != nil {
                                // Has image attachment but not downloaded
                                Button(action: downloadAndAnalyze) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.title2)
                                        Text("Download & Analyze")
                                            .font(.headline)
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: 200)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                }
                            } else {
                                // No content to analyze
                                Text("No content available to analyze")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
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
                    HStack(spacing: 12) {
                        // Local reanalyze button
                        Button(action: {
                            isReanalyzing = true
                            analyzeAssignment(useCloud: false)
                        }) {
                            Label("Local", systemImage: "brain.head.profile")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isReanalyzing || isAnalyzing)

                        // Cloud reanalyze button (only show if enabled in settings)
                        if useCloudAnalysis {
                            Button(action: {
                                isReanalyzing = true
                                analyzeAssignment(useCloud: true)
                            }) {
                                Label("Cloud", systemImage: "sparkles")
                                    .labelStyle(.iconOnly)
                            }
                            .disabled(isReanalyzing || isAnalyzing)
                        }
                    }
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

            if isAnalyzing {
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
