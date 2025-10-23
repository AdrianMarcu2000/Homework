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
    @State private var analysisError: String?
    @State private var analysisProgress: (current: Int, total: Int)?
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var selectedAttachment: Material?
    @State private var showPDFPageSelector = false
    @State private var downloadedPDFData: Data?
    @State private var selectedPDFFile: DriveFile?
    @State private var showExercises = false

    // Check if already analyzed
    private var hasAnalysis: Bool {
        assignment.analysisResult != nil && !(assignment.analysisResult?.exercises.isEmpty ?? true)
    }

    var body: some View {
        if let attachment = selectedAttachment {
            // Show selected attachment in detail view
            AttachmentContentView(material: attachment, onBack: {
                selectedAttachment = nil
            })
        } else {
            // Split view: Assignment overview on left, exercises panel on right
            splitViewContent
        }
    }

    // MARK: - Split View Content

    private var splitViewContent: some View {
        GeometryReader { geometry in
            // Full-width toggle between assignment overview and exercises
            if !showExercises {
                // Assignment overview view
                GeometryReader { contentGeometry in
                    ZStack(alignment: .trailing) {
                        assignmentOverviewView
                            .frame(width: geometry.size.width)

                        // Floating Exercises button - right middle
                        if hasAnalysis, let analysis = assignment.analysisResult {
                            Button(action: {
                                AppLogger.ui.info("User opened exercises panel for assignment")
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showExercises = true
                                }
                            }) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Exercises")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Text("\(analysis.exercises.count) found")
                                            .font(.caption)
                                            .opacity(0.9)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 12, x: -2, y: 0)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 24)
                            .position(x: contentGeometry.size.width - 100, y: contentGeometry.size.height / 2)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .frame(width: geometry.size.width)
            }

            // Exercises view with preview
            if showExercises, let analysis = assignment.analysisResult, !analysis.exercises.isEmpty {
                GeometryReader { contentGeometry in
                    ZStack(alignment: .leading) {
                        ScrollView {
                            VStack(spacing: 16) {
                                // Exercises content
                                ForEach(analysis.exercises, id: \.self) { exercise in
                                    ClassroomExerciseCard(exercise: exercise, assignment: assignment)
                                        .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom)
                        }
                        .frame(width: geometry.size.width)
                        .background(Color(UIColor.systemBackground))

                        // Back button - aligned to middle-left at same vertical position as Exercises button
                        VStack(alignment: .leading, spacing: 8) {
                            // Navigation button
                            Button(action: {
                                AppLogger.ui.info("User navigated to assignment overview from exercises")
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showExercises = false
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .semibold))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Assignment")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Text("View details")
                                            .font(.caption)
                                            .opacity(0.9)
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 2, y: 0)
                            }
                            .buttonStyle(.plain)

                            // Compact preview
                            if assignment.imageData != nil, let imageData = assignment.imageData, let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 120, maxHeight: 100)
                                    .cornerRadius(6)
                                    .shadow(radius: 2)
                            } else if let description = assignment.coursework.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(5)
                                    .padding(8)
                                    .frame(maxWidth: 120, alignment: .leading)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.leading, 24)
                        .position(x: 100, y: contentGeometry.size.height / 2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width)
                .id(assignment.analysisJSON ?? "")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle(assignment.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Apple AI button
                if AIAnalysisService.shared.isModelAvailable {
                    Button(action: { analyzeWithAI(useCloud: false) }) {
                        Image(systemName: "apple.logo")
                            .font(.body)
                    }
                    .disabled(isAnalyzing)
                }

                // Google AI button
                if useCloudAnalysis {
                    Button(action: { analyzeWithAI(useCloud: true) }) {
                        Image(systemName: "cloud")
                            .font(.body)
                    }
                    .disabled(isAnalyzing)
                }
            }
        }
        .sheet(isPresented: $showPDFPageSelector) {
            if let pdfData = downloadedPDFData, let pdfFile = selectedPDFFile {
                PDFPageSelectorView(
                    pdfData: pdfData,
                    onConfirm: { pageIndices in
                        handlePDFPageSelection(pageIndices, pdfFile: pdfFile)
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

    // MARK: - Assignment Overview (Not Analyzed)

    private var assignmentOverviewView: some View {
        VStack(spacing: 0) {
            if isAnalyzing || assignment.isDownloadingImage {
                // Show progress
                analysisProgressView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Assignment description
                        if let description = assignment.coursework.description, !description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Assignment Description")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text(description)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }

                        // Attachments list
                        if let materials = assignment.coursework.materials, !materials.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Attachments")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                                    AttachmentRowButton(material: material) {
                                        selectedAttachment = material
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                    }
                    .padding(.vertical)
                }
            }
        }
        .sheet(isPresented: $showPDFPageSelector) {
            if let pdfData = downloadedPDFData, let pdfFile = selectedPDFFile {
                PDFPageSelectorView(
                    pdfData: pdfData,
                    onConfirm: { pageIndices in
                        handlePDFPageSelection(pageIndices, pdfFile: pdfFile)
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

    // MARK: - Analysis Progress

    private var analysisProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            if assignment.isDownloadingImage {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Downloading attachments...")
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
    }

    // MARK: - Analysis Actions

    private func analyzeWithAI(useCloud: Bool) {
        AppLogger.ui.info("User tapped analyze with \(useCloud ? "Google" : "Apple") AI")

        Task {
            // Start analysis
            await MainActor.run {
                isAnalyzing = true
                analysisError = nil
                analysisProgress = nil
            }

            do {
                // Try to download image/PDF attachments (may return empty array or throw error)
                let images = try await assignment.downloadAllAttachments()

                AppLogger.image.info("Downloaded \(images.count) attachment images for analysis")

                if images.isEmpty {
                    // Text-only analysis - check if we have extracted text from ODT
                    if let extractedText = assignment.extractedText, !extractedText.isEmpty {
                        AppLogger.ai.info("Using extracted text from ODT (\(extractedText.count) chars) for analysis")
                        analyzeTextOnly(text: extractedText, useCloud: useCloud)
                    } else {
                        // Use assignment description for text-only analysis
                        let fullText = assignment.coursework.description ?? ""
                        analyzeTextOnly(text: fullText, useCloud: useCloud)
                    }
                } else if images.count == 1 {
                    // Single image analysis
                    analyzeWithImage(image: images[0], useCloud: useCloud)
                } else {
                    // Multiple images analysis
                    analyzeMultipleImages(images: images, useCloud: useCloud)
                }

            } catch {
                // If no attachments, try text-only analysis with description
                let fullText = assignment.coursework.description ?? ""

                if let extractedText = assignment.extractedText, !extractedText.isEmpty {
                    // Use extracted ODT text if available
                    AppLogger.ai.info("No attachments, using extracted ODT text (\(extractedText.count) chars) for analysis")
                    analyzeTextOnly(text: extractedText, useCloud: useCloud)
                } else if !fullText.isEmpty {
                    // Use assignment description if available
                    AppLogger.ai.info("No attachments, using assignment description (\(fullText.count) chars) for text-only analysis")
                    analyzeTextOnly(text: fullText, useCloud: useCloud)
                } else {
                    // No content at all to analyze
                    await MainActor.run {
                        isAnalyzing = false
                        analysisError = "This assignment has no content to analyze. Please add a description or attach files."
                        AppLogger.google.error("No content available for analysis", error: error)
                    }
                }
            }
        }
    }

    private func analyzeWithImage(image: UIImage, useCloud: Bool) {
        let assignmentDescription = assignment.coursework.description ?? ""

        // Perform OCR
        OCRService.shared.recognizeTextWithBlocks(from: image) { result in
            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    // Combine assignment description with OCR text
                    let combinedText: String
                    if !assignmentDescription.isEmpty {
                        combinedText = "Assignment Description:\n\(assignmentDescription)\n\nAttachment Content:\n\(ocrResult.fullText)"
                        AppLogger.ai.info("Combined assignment description (\(assignmentDescription.count) chars) with OCR text (\(ocrResult.fullText.count) chars)")
                    } else {
                        combinedText = ocrResult.fullText
                    }

                    assignment.extractedText = combinedText

                    // Store combined image
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        assignment.imageData = imageData
                    }
                }

                // Analyze with AI - prepend assignment description to OCR blocks
                var aiBlocks = ocrResult.blocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

                // If we have assignment description, add it as a block at the top
                if !assignmentDescription.isEmpty {
                    let descriptionBlock = AIAnalysisService.OCRBlock(text: "Assignment Description:\n\(assignmentDescription)\n\nAttachment Content:", y: 1.0)
                    aiBlocks.insert(descriptionBlock, at: 0)
                }

                if useCloud {
                    analyzeWithCloud(image: image, ocrBlocks: aiBlocks)
                } else {
                    analyzeWithLocal(image: image, ocrBlocks: aiBlocks)
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

    private func analyzeMultipleImages(images: [UIImage], useCloud: Bool) {
        let assignmentDescription = assignment.coursework.description ?? ""

        // Combine images
        guard let combinedImage = PDFProcessingService.shared.combineImages(images, spacing: 20) else {
            isAnalyzing = false
            analysisError = "Failed to combine images"
            return
        }

        // Store combined image
        if let imageData = combinedImage.jpegData(compressionQuality: 0.8) {
            assignment.imageData = imageData
        }

        // Perform OCR
        OCRService.shared.recognizeTextWithBlocks(from: combinedImage) { result in
            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    // Combine assignment description with OCR text
                    let combinedText: String
                    if !assignmentDescription.isEmpty {
                        combinedText = "Assignment Description:\n\(assignmentDescription)\n\nAttachment Content:\n\(ocrResult.fullText)"
                        AppLogger.ai.info("Combined assignment description (\(assignmentDescription.count) chars) with OCR text (\(ocrResult.fullText.count) chars)")
                    } else {
                        combinedText = ocrResult.fullText
                    }

                    assignment.extractedText = combinedText
                }

                // Prepare OCR blocks with assignment description
                var aiBlocks = ocrResult.blocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

                // If we have assignment description, add it as a block at the top
                if !assignmentDescription.isEmpty {
                    let descriptionBlock = AIAnalysisService.OCRBlock(text: "Assignment Description:\n\(assignmentDescription)\n\nAttachment Content:", y: 1.0)
                    aiBlocks.insert(descriptionBlock, at: 0)
                }

                // Always use cloud for multi-image
                CloudAnalysisService.shared.analyzeHomework(images: images, ocrBlocks: aiBlocks) { result in
                    handleAnalysisResult(result)
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

    private func analyzeTextOnly(text: String, useCloud: Bool) {
        assignment.extractedText = text

        if useCloud {
            // Use cloud analysis for text-only
            CloudAnalysisService.shared.analyzeTextOnly(text: text) { result in
                handleAnalysisResult(result)
            }
        } else {
            // Use local Apple AI for text-only
            AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
                handleAnalysisResult(result)
            }
        }
    }

    private func analyzeWithLocal(image: UIImage, ocrBlocks: [AIAnalysisService.OCRBlock]) {
        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: ocrBlocks,
            progressHandler: { current, total in
                DispatchQueue.main.async {
                    analysisProgress = (current, total)
                }
            }
        ) { result in
            handleAnalysisResult(result)
        }
    }

    private func analyzeWithCloud(image: UIImage, ocrBlocks: [AIAnalysisService.OCRBlock]) {
        CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: ocrBlocks) { result in
            handleAnalysisResult(result)
        }
    }

    private func handleAnalysisResult(_ result: Result<AIAnalysisService.AnalysisResult, Error>) {
        DispatchQueue.main.async {
            isAnalyzing = false
            analysisProgress = nil

            switch result {
            case .success(let analysis):
                saveAnalysisResult(analysis)
                AppLogger.ai.info("Analysis complete - Found \(analysis.exercises.count) exercises")

                // Navigate to exercises view after successful analysis
                showExercises = true

            case .failure(let error):
                analysisError = error.localizedDescription
                AppLogger.ai.error("Analysis failed", error: error)
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

                // Extract subject
                if let subject = analysis.exercises.first(where: { $0.subject != nil })?.subject {
                    assignment.subject = subject
                }

                assignment.saveToCache()
                AppLogger.persistence.info("Analysis saved - Exercises: \(analysis.exercises.count)")
            }
        } catch {
            AppLogger.persistence.error("Error encoding analysis", error: error)
        }
    }

    private func handlePDFPageSelection(_ pageIndices: [Int], pdfFile: DriveFile) {
        showPDFPageSelector = false

        Task {
            do {
                let images = try await assignment.downloadAndProcessPDF(driveFile: pdfFile, pageIndices: pageIndices)

                await MainActor.run {
                    if images.count == 1 {
                        analyzeWithImage(image: images[0], useCloud: false)
                    } else {
                        analyzeMultipleImages(images: images, useCloud: false)
                    }
                }
            } catch {
                await MainActor.run {
                    analysisError = error.localizedDescription
                    AppLogger.google.error("Failed to process PDF pages", error: error)
                }
            }
        }
    }
}

// MARK: - Attachment Row Button

private struct AttachmentRowButton: View {
    let material: Material
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                if let driveFile = material.driveFile?.driveFile {
                    let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

                    if fileExtension == "pdf" {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    } else if fileExtension == "odt" {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                    } else if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(driveFile.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        Text(fileExtension.uppercased())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let link = material.link {
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(link.title ?? "Link")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(link.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Attachment Content View

private struct AttachmentContentView: View {
    let material: Material
    let onBack: () -> Void
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .padding()

                Spacer()
            }
            .background(Color(UIColor.systemBackground))

            Divider()

            // Content
            if isLoading {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading attachment...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Failed to load attachment")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                attachmentContent
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadAttachment()
        }
    }

    @ViewBuilder
    private var attachmentContent: some View {
        if let driveFile = material.driveFile?.driveFile {
            driveFileViewer(driveFile)
        } else if let link = material.link {
            linkViewer(link)
        } else {
            Text("Unsupported attachment type")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            if let fileData = fileData, let image = UIImage(data: fileData) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                }
            }
        } else if fileExtension == "pdf" {
            if let fileData = fileData, let pdfDocument = PDFDocument(data: fileData) {
                AssignmentPDFView(document: pdfDocument)
            }
        } else if fileExtension == "odt" {
            if let fileData = fileData {
                ODTViewerContent(odtData: fileData, fileName: driveFile.title)
            }
        }
    }

    @ViewBuilder
    private func linkViewer(_ link: Link) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            if let title = link.title {
                Text(title)
                    .font(.headline)
            }

            Text(link.url)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()

            if let url = URL(string: link.url) {
                SwiftUI.Link("Open Link", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    private func loadAttachment() {
        guard let driveFile = material.driveFile?.driveFile else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                await MainActor.run {
                    fileData = data
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - ODT Viewer Content

private struct ODTViewerContent: View {
    let odtData: Data
    let fileName: String
    @State private var content: ODTProcessingService.ODTContent?
    @State private var isProcessing = true

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Processing ODT...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let content = content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !content.text.isEmpty {
                            Text(content.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                        }

                        ForEach(Array(content.images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .task {
            // Process ODT in background
            let extractedContent = await Task.detached {
                await ODTProcessingService.shared.extractContent(from: odtData)
            }.value

            content = extractedContent
            isProcessing = false
        }
    }

    init(odtData: Data, fileName: String) {
        self.odtData = odtData
        self.fileName = fileName
    }
}

// MARK: - PDF Viewer

import PDFKit

private struct AssignmentPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - Exercise Card

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
