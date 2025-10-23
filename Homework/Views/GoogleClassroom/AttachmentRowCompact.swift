
//
//  AttachmentRowCompact.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

// MARK: - Compact Attachment Row

struct AttachmentRowCompact: View {
    let material: Material
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            if let driveFile = material.driveFile?.driveFile {
                AppLogger.ui.info("User tapped attachment in tree: \(driveFile.title)")
            }
            onSelect()
        }) {
            HStack(spacing: 8) {
                // Icon based on attachment type
                if let driveFile = material.driveFile?.driveFile {
                    let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()
                    if fileExtension == "pdf" {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.red)
                    } else if fileExtension == "odt" {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.purple)
                    } else if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.gray)
                    }

                    Text(driveFile.title)
                        .font(.caption)
                        .lineLimit(1)
                } else if let link = material.link {
                    Image(systemName: "link")
                        .foregroundColor(.orange)
                    Text(link.title ?? link.url)
                        .font(.caption)
                        .lineLimit(1)
                } else if let video = material.youtubeVideo {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.red)
                    Text(video.title)
                        .font(.caption)
                        .lineLimit(1)
                } else if let form = material.form {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.green)
                    Text(form.title)
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
