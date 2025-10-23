
//
//  AttachmentRowButton.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

struct AttachmentRowButton: View {
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
