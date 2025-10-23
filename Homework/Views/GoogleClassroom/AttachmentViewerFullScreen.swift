
//
//  AttachmentViewerFullScreen.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import PDFKit
import OSLog

// MARK: - Full Screen Attachment Viewer

struct AttachmentViewerFullScreen: View {
    let material: Material
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Main content
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading attachment...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
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
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    attachmentContent
                }
            }

            // Close button overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 36, height: 36)
                            )
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
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
        } else if let video = material.youtubeVideo {
            videoViewer(video)
        } else if let form = material.form {
            formViewer(form)
        } else {
            Text("Unsupported attachment type")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            // Full screen image viewer
            if let fileData = fileData, let image = UIImage(data: fileData) {
                FullScreenImageViewer(image: image, title: driveFile.title)
            } else {
                Text("Loading image...")
                    .foregroundColor(.white)
            }
        } else if fileExtension == "pdf" {
            // Full screen PDF viewer
            if let fileData = fileData {
                FullScreenPDFViewer(pdfData: fileData, title: driveFile.title)
            } else {
                Text("Loading PDF...")
                    .foregroundColor(.white)
            }
        } else {
            // Generic file - show info on dark background
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                Text(driveFile.title)
                    .font(.headline)
                    .foregroundColor(.white)
                if let url = URL(string: driveFile.alternateLink) {
                    SwiftUI.Link("Open in Drive", destination: url)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func linkViewer(_ link: ClassroomLink) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            if let title = link.title {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
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
        }
        .padding()
    }

    @ViewBuilder
    private func videoViewer(_ video: YouTubeVideo) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text(video.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: video.alternateLink) {
                SwiftUI.Link("Watch on YouTube", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func formViewer(_ form: Form) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text(form.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: form.formUrl) {
                SwiftUI.Link("Open Form", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func loadAttachment() {
        // Only load Drive files (images and PDFs)
        guard let driveFile = material.driveFile?.driveFile else {
            // Links, videos, and forms don't need loading
            return
        }

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
                AppLogger.google.error("Failed to load attachment", error: error)
            }
        }
    }
}
