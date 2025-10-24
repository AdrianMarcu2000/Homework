//
//  AttachmentPreviewCard.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

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
                            .scaledToFit()
                            .frame(width: 280, height: 373)
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
        guard ["pdf", "odt", "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(ext) else {
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
                    if let rawPreview = PDFProcessingService.shared.extractPages(from: pdfData, pageIndices: [0], scale: 1.0).first {
                        // Resize to preview preset for optimal card display
                        let preview = rawPreview.resized(for: .preview)

                        await MainActor.run {
                            self.previewImage = preview
                            self.isLoadingPreview = false
                            AppLogger.google.info("✅ Loaded PDF preview for: \(driveFile.title) (ID: \(uniqueID))")
                        }
                    }
                } else if ext == "odt" {
                    // Download and render first page from ODT
                    AppLogger.google.info("📥 Downloading ODT: \(driveFile.title)")
                    let odtData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                    AppLogger.google.info("📄 Rendering first page from ODT: \(driveFile.title)")

                    if let rawPreview = ODTProcessingService.shared.renderFirstPage(from: odtData, size: CGSize(width: 280, height: 373)) {
                        // Already sized for preview, but ensure file size is optimized
                        let preview = rawPreview.resized(for: .preview)

                        await MainActor.run {
                            self.previewImage = preview
                            self.isLoadingPreview = false
                            AppLogger.google.info("✅ Loaded ODT preview for: \(driveFile.title) (ID: \(uniqueID))")
                        }
                    } else {
                        // Rendering failed, show icon
                        await MainActor.run {
                            self.isLoadingPreview = false
                            AppLogger.google.info("ℹ️ Failed to render ODT preview, showing icon: \(driveFile.title) (ID: \(uniqueID))")
                        }
                    }
                } else {
                    // Download image directly
                    AppLogger.google.info("📥 Downloading image: \(driveFile.title)")
                    let imageData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)

                    if let rawImage = UIImage(data: imageData) {
                        // Resize to preview preset for optimal card display
                        let preview = rawImage.resized(for: .preview)

                        await MainActor.run {
                            self.previewImage = preview
                            self.isLoadingPreview = false
                            AppLogger.google.info("✅ Loaded image preview for: \(driveFile.title) (ID: \(uniqueID))")
                        }
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
