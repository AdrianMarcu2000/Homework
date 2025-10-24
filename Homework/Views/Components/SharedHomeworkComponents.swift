//
//  SharedHomeworkComponents.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

// MARK: - Analysis Progress View

/// Shared analysis progress view that works with any analyzer
struct AnalysisProgressView: View {
    var progress: (current: Int, total: Int)?
    var isCloudAnalysis: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = progress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text(isCloudAnalysis ? "Analyzing with cloud AI..." : "Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }
}

// MARK: - Homework Image/Content Display

/// Shared homework content display (image or text)
struct HomeworkContentView<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
        let _ = {
            let hasImageData = homework.imageData != nil
            let imageDataSize = homework.imageData?.count ?? 0
            let hasExtractedText = homework.extractedText != nil
            let extractedTextLength = homework.extractedText?.count ?? 0
            let hasDescription = (homework as? ClassroomAssignment)?.coursework.description != nil
            let descriptionLength = (homework as? ClassroomAssignment)?.coursework.description?.count ?? 0
            let materialsCount = (homework as? ClassroomAssignment)?.coursework.materials?.count ?? 0

            AppLogger.ui.info("📄 HomeworkContentView rendering - imageData: \(hasImageData) (\(imageDataSize) bytes), extractedText: \(hasExtractedText) (\(extractedTextLength) chars), description: \(hasDescription) (\(descriptionLength) chars), materials: \(materialsCount)")
        }()

        VStack(spacing: 20) {
            // Show assignment description first if it's a ClassroomAssignment
            if let assignment = homework as? ClassroomAssignment,
               let description = assignment.coursework.description,
               !description.isEmpty {
                let _ = AppLogger.ui.info("✅ Displaying assignment description (\(description.count) chars)")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Assignment")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            }

            // Show attachments section for ClassroomAssignments
            if let assignment = homework as? ClassroomAssignment,
               let materials = assignment.coursework.materials, !materials.isEmpty {
                let _ = AppLogger.ui.info("📎 Displaying \(materials.count) attachment preview cards")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Attachments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Show preview cards for all materials
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                                let materialID = generateMaterialID(assignment: assignment, material: material, index: index)
                                let filename = material.driveFile?.driveFile.title ?? material.link?.title ?? material.youtubeVideo?.title ?? material.form?.title ?? "unknown"
                                NavigationLink(destination: AttachmentViewerView(material: material)) {
                                    AttachmentPreviewCard(
                                        material: material,
                                        assignment: assignment
                                    )
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    AppLogger.ui.info("User tapped attachment preview: \(filename)")
                                })
                                .id(materialID)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
            }

            // Show downloaded image content if available (only for non-ClassroomAssignment items)
            if !(homework is ClassroomAssignment),
               let imageData = homework.imageData,
               let uiImage = UIImage(data: imageData) {
                let _ = AppLogger.ui.info("✅ Displaying downloaded image (\(imageData.count) bytes)")

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding(.horizontal)
            } else if let extractedText = homework.extractedText, !extractedText.isEmpty, !(homework is ClassroomAssignment) {
                // For non-ClassroomAssignment items, show extracted text
                let _ = AppLogger.ui.info("✅ Displaying extracted text content (\(extractedText.count) chars)")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Extracted Text")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Text(extractedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            } else if !(homework is ClassroomAssignment) || (homework as? ClassroomAssignment)?.coursework.description?.isEmpty ?? true {
                // Only show "No Content" if there's truly no content
                let _ = AppLogger.ui.info("⚠️ Showing 'No Content' - no description, imageData, or extractedText available")
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Content")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }

    /// Generate unique ID for material to prevent SwiftUI view reuse across assignments
    private func generateMaterialID(assignment: ClassroomAssignment, material: Material, index: Int) -> String {
        let assignmentID = assignment.id
        if let driveFile = material.driveFile?.driveFile {
            return "\(assignmentID)_\(driveFile.id)_\(index)"
        } else if let link = material.link {
            return "\(assignmentID)_\(link.url.hashValue)_\(index)"
        } else if let video = material.youtubeVideo {
            return "\(assignmentID)_\(video.id)_\(index)"
        } else if let form = material.form {
            return "\(assignmentID)_\(form.formUrl.hashValue)_\(index)"
        }
        return "\(assignmentID)_\(index)"
    }
}

// MARK: - AI Analysis Buttons

/// Shared AI analysis button row
struct AIAnalysisButtons: View {
    var hasAnalysis: Bool
    var isAnalyzing: Bool
    var onAnalyzeWithApple: () -> Void
    var onAnalyzeWithCloud: () -> Void
    var onViewExercises: (() -> Void)?

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var body: some View {
        VStack(spacing: 12) {
            Text(hasAnalysis ? "Actions" : "Analyze with AI")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // Apple AI button
                if AIAnalysisService.shared.isModelAvailable {
                    Button(action: {
                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Apple AI")
                        onAnalyzeWithApple()
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: "apple.logo")
                                .font(.title2)
                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                .font(.caption)
                            if !hasAnalysis {
                                Text("Apple AI")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, hasAnalysis ? 12 : 16)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(10)
                    }
                    .disabled(isAnalyzing)
                }

                // Google AI button
                if useCloudAnalysis {
                    Button(action: {
                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Cloud AI")
                        onAnalyzeWithCloud()
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: "cloud.fill")
                                .font(.title2)
                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                .font(.caption)
                            if !hasAnalysis {
                                Text("Google AI")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, hasAnalysis ? 12 : 16)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(10)
                    }
                    .disabled(isAnalyzing)
                }

                // View Exercises button (only when analyzed)
                if hasAnalysis, let viewExercises = onViewExercises {
                    Button(action: {
                        AppLogger.ui.info("User tapped view exercises")
                        viewExercises()
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: "pencil.and.list.clipboard")
                                .font(.title2)
                            Text("View Exercises")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
}

// MARK: - Exercises List

/// Shared exercises list view
struct ExercisesListView<Homework: AnalyzableHomework>: View {
    var analysis: AnalysisResult
    var homework: Homework
    var onAnswerChange: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(analysis.exercises, id: \.self) { exercise in
                    ExerciseCardView(
                        exercise: exercise,
                        homework: homework,
                        onAnswerChange: onAnswerChange
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Attachment Preview Card

/// Preview card for attachments with thumbnail and tap action
struct AttachmentPreviewCard: View {
    let material: Material
    let assignment: ClassroomAssignment

    @State private var previewImage: UIImage?
    @State private var isLoadingPreview = false

    // Unique ID based on assignment and material to force reload when switching assignments
    private var uniqueID: String {
        if let driveFile = material.driveFile?.driveFile {
            return "\(assignment.id)_\(driveFile.id)"
        } else if let link = material.link {
            return "\(assignment.id)_\(link.url)"
        } else if let video = material.youtubeVideo {
            return "\(assignment.id)_\(video.id)"
        } else if let form = material.form {
            return "\(assignment.id)_\(form.formUrl)"
        }
        return assignment.id
    }

    private var fileInfo: (name: String, icon: String, color: Color, label: String)? {
        if let driveFile = material.driveFile?.driveFile {
            let ext = (driveFile.title as NSString).pathExtension.lowercased()

            switch ext {
            case "pdf":
                return (driveFile.title, "doc.fill", .red, "PDF")
            case "doc", "docx":
                return (driveFile.title, "doc.text.fill", .blue, "DOC")
            case "xls", "xlsx":
                return (driveFile.title, "tablecells.fill", .green, "XLS")
            case "ppt", "pptx":
                return (driveFile.title, "rectangle.stack.fill", .orange, "PPT")
            case "odt":
                return (driveFile.title, "doc.text.fill", .purple, "ODT")
            case "txt":
                return (driveFile.title, "doc.plaintext.fill", .gray, "TXT")
            case "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp":
                return (driveFile.title, "photo.fill", .blue, "IMG")
            case "zip", "rar", "7z":
                return (driveFile.title, "archivebox.fill", .brown, "ZIP")
            default:
                return (driveFile.title, "doc.fill", .gray, "FILE")
            }
        } else if let link = material.link {
            return (link.title ?? link.url, "link", .orange, "LINK")
        } else if let video = material.youtubeVideo {
            return (video.title, "play.rectangle.fill", .red, "VIDEO")
        } else if let form = material.form {
            return (form.title, "list.bullet.clipboard", .green, "FORM")
        }

        return nil
    }

    var body: some View {
        if let info = fileInfo {
            VStack(spacing: 8) {
                // Preview thumbnail or icon
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 373)
                            .clipped()
                            .cornerRadius(10)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(info.color.opacity(0.1))
                            .frame(width: 280, height: 373)
                            .overlay(
                                VStack(spacing: 8) {
                                    if isLoadingPreview {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: info.icon)
                                            .font(.system(size: 32))
                                            .foregroundColor(info.color)
                                    }

                                    Text(info.label)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(info.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(info.color.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            )
                    }

                    // Overlay file type badge on preview
                    if previewImage != nil {
                        VStack {
                            HStack {
                                Spacer()
                                Text(info.label)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(info.color)
                                    .cornerRadius(4)
                                    .shadow(radius: 2)
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                .frame(width: 280, height: 373)

                // File name
                Text(info.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .id(uniqueID)
            .onAppear {
                loadPreview()
            }
            .onDisappear {
                // Clear preview when view disappears to prevent showing wrong preview
                AppLogger.ui.info("🗑️ Clearing preview for: \(uniqueID)")
                previewImage = nil
                isLoadingPreview = false
            }
        }
    }

    private func loadPreview() {
        // Only load previews for downloadable files
        guard let driveFile = material.driveFile?.driveFile else { return }

        let ext = (driveFile.title as NSString).pathExtension.lowercased()

        // Only generate previews for supported types
        guard ["pdf", "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(ext) else {
            return
        }

        // ALWAYS reset state before loading - no caching, no optimization
        AppLogger.google.info("🔄 [FRESH LOAD] Starting preview load for: \(driveFile.title) (ID: \(uniqueID))")
        previewImage = nil
        isLoadingPreview = true

        Task {
            do {
                if ext == "pdf" {
                    // Download and extract first page
                    AppLogger.google.info("📥 Downloading PDF: \(driveFile.title)")
                    let pdfData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                    AppLogger.google.info("📄 Extracting first page from PDF: \(driveFile.title)")
                    let preview = PDFProcessingService.shared.extractPages(from: pdfData, pageIndices: [0], scale: 1.0).first

                    await MainActor.run {
                        self.previewImage = preview
                        self.isLoadingPreview = false
                        AppLogger.google.info("✅ Loaded PDF preview for: \(driveFile.title) (ID: \(uniqueID))")
                    }
                } else {
                    // Download image directly
                    AppLogger.google.info("📥 Downloading image: \(driveFile.title)")
                    let imageData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)

                    await MainActor.run {
                        self.previewImage = UIImage(data: imageData)
                        self.isLoadingPreview = false
                        AppLogger.google.info("✅ Loaded image preview for: \(driveFile.title) (ID: \(uniqueID))")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingPreview = false
                    AppLogger.google.error("❌ Failed to load preview for: \(driveFile.title) (ID: \(uniqueID))", error: error)
                }
            }
        }
    }
}

// MARK: - Toolbar Title

/// Shared toolbar title view for homework items
struct HomeworkToolbarTitle<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
        VStack(spacing: 2) {
            Text(homework.title)
                .font(.headline)
                .fontWeight(.semibold)
            if let date = homework.date {
                Text(date, formatter: itemFormatter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
