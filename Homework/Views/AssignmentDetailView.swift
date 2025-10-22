//
//  AssignmentDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import PencilKit
import OSLog

/// View for displaying and analyzing a Google Classroom assignment
struct AssignmentDetailView: View {
    @ObservedObject var assignment: ClassroomAssignment
    @State private var isAnalyzing = false
    @State private var isReanalyzing = false
    @State private var analysisError: String?
    @State private var analysisProgress: (current: Int, total: Int)?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var showSubmissionView = false
    @State private var showPDFPageSelector = false
    @State private var downloadedPDFData: Data?
    @State private var selectedPDFFile: DriveFile?
    @State private var multipleImages: [UIImage] = []

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
                    VStack(spacing: 12) {
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
                                    } else if let text = assignment.extractedText ?? assignment.coursework.description {
                                        analyzeTextOnlyCloud(text: text)
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
                                .disabled(isReanalyzing || assignment.isDownloadingImage)
                            }
                        }

                        // Submit Homework button
                        Button(action: {
                            showSubmissionView = true
                        }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .font(.title3)
                                Text("Submit Homework")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
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
                                } else if let text = assignment.extractedText ?? assignment.coursework.description {
                                    analyzeTextOnlyCloud(text: text)
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
                            .disabled(isAnalyzing || assignment.isDownloadingImage)
                        }
                        
                        // Download and Analyze button - show if there are any attachments
                        if assignment.imageData == nil && !assignment.allImageAndPDFMaterials.isEmpty {
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
        .overlay {
            if showSubmissionView {
                HomeworkSubmissionView(assignment: assignment, onDismiss: {
                    showSubmissionView = false
                })
            }
        }
        .sheet(isPresented: $showPDFPageSelector) {
            if let pdfData = downloadedPDFData {
                PDFPageSelectorView(
                    pdfData: pdfData,
                    onConfirm: { pageIndices in
                        handlePDFPageSelection(pageIndices)
                    },
                    onCancel: {
                        showPDFPageSelector = false
                        downloadedPDFData = nil
                        selectedPDFFile = nil
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func downloadAndAnalyze() {
        Task {
            do {
                let files = assignment.allImageAndPDFMaterials

                // Check if there's a PDF that needs page selection
                if let pdfFile = files.first(where: { ($0.title as NSString).pathExtension.lowercased() == "pdf" }) {
                    // Download PDF and check page count
                    let pdfData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: pdfFile.id)

                    if let pageCount = PDFProcessingService.shared.getPageCount(from: pdfData) {
                        if pageCount > 3 {
                            // Show page selector
                            await MainActor.run {
                                self.downloadedPDFData = pdfData
                                self.selectedPDFFile = pdfFile
                                self.showPDFPageSelector = true
                            }
                            return
                        }
                    }
                }

                // No PDF or PDF has 3 or fewer pages - download and analyze all attachments
                let images = try await assignment.downloadAllAttachments()

                await MainActor.run {
                    self.multipleImages = images
                }

                // Analyze based on image count
                if images.count == 1 {
                    analyzeAssignment(useCloud: false)
                } else {
                    analyzeMultipleImages(images: images, useCloud: false)
                }
            } catch {
                analysisError = error.localizedDescription
                AppLogger.google.error("Failed to download attachments", error: error)
            }
        }
    }

    private func handlePDFPageSelection(_ pageIndices: [Int]) {
        guard let pdfFile = selectedPDFFile else {
            return
        }

        showPDFPageSelector = false

        Task {
            do {
                let images = try await assignment.downloadAndProcessPDF(driveFile: pdfFile, pageIndices: pageIndices)

                await MainActor.run {
                    self.multipleImages = images
                }

                // Analyze the selected pages
                if images.count == 1 {
                    analyzeAssignment(useCloud: false)
                } else {
                    analyzeMultipleImages(images: images, useCloud: false)
                }
            } catch {
                analysisError = error.localizedDescription
                AppLogger.google.error("Failed to process PDF pages", error: error)
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
                    AppLogger.ocr.error("OCR failed", error: error)
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
                    AppLogger.ai.error("Analysis failed", error: error)
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
                    AppLogger.cloud.error("Cloud analysis failed", error: error)
                }
            }
        }
    }

    // MARK: - Multi-Image Analysis

    private func analyzeMultipleImages(images: [UIImage], useCloud: Bool) {
        isAnalyzing = true
        analysisError = nil
        analysisProgress = nil

        AppLogger.ai.info("Starting multi-image analysis with \(images.count) images")

        // Combine all images into one for OCR
        guard let combinedImage = PDFProcessingService.shared.combineImages(images, spacing: 20) else {
            isAnalyzing = false
            analysisError = "Failed to combine images"
            return
        }

        // Perform OCR on combined image
        OCRService.shared.recognizeTextWithBlocks(from: combinedImage) { result in
            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    assignment.extractedText = ocrResult.fullText
                }

                // Analyze with cloud AI (always use cloud for multi-image)
                let aiBlocks = ocrResult.blocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

                CloudAnalysisService.shared.analyzeHomework(images: images, ocrBlocks: aiBlocks) { result in
                    DispatchQueue.main.async {
                        isAnalyzing = false
                        analysisProgress = nil

                        switch result {
                        case .success(let analysis):
                            saveAnalysisResult(analysis)
                            AppLogger.cloud.info("Multi-image analysis complete - Found \(analysis.exercises.count) exercises")

                        case .failure(let error):
                            analysisError = error.localizedDescription
                            AppLogger.cloud.error("Multi-image analysis failed", error: error)
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    isAnalyzing = false
                    analysisError = error.localizedDescription
                    AppLogger.ocr.error("OCR failed on combined image", error: error)
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

                // Extract subject from the first exercise with a subject
                if let subject = analysis.exercises.first(where: { $0.subject != nil })?.subject {
                    assignment.subject = subject
                }

                assignment.saveToCache()
                AppLogger.persistence.info("Analysis saved to cache - Exercises: \(analysis.exercises.count)")
            }
        } catch {
            AppLogger.persistence.error("Error encoding analysis", error: error)
        }
    }

    // MARK: - Text Analysis

    /// Analyze text-only assignment using AI (no image available)
    private func analyzeTextOnly(text: String) {
        isAnalyzing = true
        analysisError = nil

        // Store the original text as extractedText
        assignment.extractedText = text

        AppLogger.ai.info("Starting text analysis for assignment (Apple AI)")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                isAnalyzing = false

                switch result {
                case .success(let analysis):
                    AppLogger.ai.info("Text analysis complete - Found \(analysis.exercises.count) exercises")
                    saveAnalysisResult(analysis)

                case .failure(let error):
                    AppLogger.ai.error("Text analysis failed", error: error)
                    analysisError = error.localizedDescription
                }
            }
        }
    }

    /// Analyze text-only assignment using Cloud AI (Google Gemini)
    private func analyzeTextOnlyCloud(text: String) {
        isAnalyzing = true
        analysisError = nil

        // Store the original text as extractedText
        assignment.extractedText = text

        AppLogger.cloud.info("Starting text analysis for assignment (Google AI)")

        // Use Cloud analysis service for text-only homework
        // Note: CloudAnalysisService doesn't have a dedicated text-only method yet,
        // so we fall back to Apple AI for text analysis
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                isAnalyzing = false

                switch result {
                case .success(let analysis):
                    AppLogger.cloud.info("Text analysis complete - Found \(analysis.exercises.count) exercises")
                    saveAnalysisResult(analysis)

                case .failure(let error):
                    AppLogger.cloud.error("Text analysis failed", error: error)
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
