
//
//  AttachmentDetailView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

/// View for displaying an attachment in the detail pane
struct AttachmentDetailView: View {
    let material: Material
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading attachment...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
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
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                attachmentContent
            }
        }
        .onAppear {
            loadAttachment()
        }
        .onChange(of: material.driveFile?.driveFile.id) { _, _ in
            // Clear cached data when switching to a different file
            fileData = nil
            errorMessage = nil
            loadAttachment()
        }
    }

    @ViewBuilder
    private var attachmentContent: some View {
        if let driveFile = material.driveFile?.driveFile {
            driveFileViewer(driveFile)
        } else if let link = material.link {
            linkViewer(link)
        } else if let video = material.youtubeVideo {
            videoViewer(video)
        } else if let form = material.form {
            formViewer(form)
        } else {
            Text("Unsupported attachment type")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        let _ = AppLogger.ui.info("Displaying Drive file: \(driveFile.title), extension: \(fileExtension), hasData: \(fileData != nil)")

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            // Image viewer
            let _ = AppLogger.ui.info("File is image type, fileData size: \(fileData?.count ?? 0) bytes")
            if let fileData = fileData {
                if let image = UIImage(data: fileData) {
                    let _ = AppLogger.ui.info("Image loaded successfully, size: \(image.size)")
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    }
                } else {
                    let _ = AppLogger.image.error("Failed to create UIImage from data")

                    // Log data preview for debugging
                    let previewLength = min(16, fileData.count)
                    let preview = fileData.prefix(previewLength).map { String(format: "%02x", $0) }.joined(separator: " ")
                    let _ = AppLogger.image.info("Image data preview (first \(previewLength) bytes): \(preview)")

                    VStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("Failed to load image")
                            .font(.headline)
                        Text("\(fileData.count) bytes received")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Loading image...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else if fileExtension == "pdf" {
            // PDF viewer
            if let fileData = fileData {
                PDFDetailViewer(pdfData: fileData)
            } else {
                VStack {
                    Spacer()
                    Text("Loading PDF...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else if fileExtension == "odt" {
            // ODT viewer
            if let fileData = fileData {
                ODTDetailViewer(odtData: fileData, fileName: driveFile.title)
            } else {
                VStack {
                    Spacer()
                    Text("Loading ODT...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else {
            // Generic file - show info
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text(driveFile.title)
                    .font(.headline)
                if let url = URL(string: driveFile.alternateLink) {
                    SwiftUI.Link("Open in Drive", destination: url)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
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
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: link.url) {
                SwiftUI.Link("Open Link", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func videoViewer(_ video: YouTubeVideo) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text(video.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: video.alternateLink) {
                SwiftUI.Link("Watch on YouTube", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func formViewer(_ form: Form) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text(form.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: form.formUrl) {
                SwiftUI.Link("Open Form", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    private func loadAttachment() {
        // Only load Drive files (images and PDFs)
        guard let driveFile = material.driveFile?.driveFile else {
            // Links, videos, and forms don't need loading
            AppLogger.ui.info("Attachment is not a Drive file, skipping download")
            return
        }

        AppLogger.ui.info("Loading Drive file: \(driveFile.title)")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                await MainActor.run {
                    fileData = data
                    isLoading = false
                    AppLogger.ui.info("Successfully loaded \(data.count) bytes for \(driveFile.title)")
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                AppLogger.google.error("Failed to load attachment", error: error)
            }
        }
    }
}
