
//
//  AttachmentContentView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import PDFKit

struct AttachmentContentView: View {
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
