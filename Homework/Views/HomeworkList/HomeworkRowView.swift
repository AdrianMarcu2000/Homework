
//
//  HomeworkRowView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// A row view displaying a single homework item in the list.
struct HomeworkRowView: View {
    @ObservedObject var item: Item

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail image
            if let imageData = item.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                // Placeholder if no image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .foregroundColor(.secondary)
                    )
            }

            // Text preview and timestamp
            VStack(alignment: .leading, spacing: 4) {
                if let text = item.extractedText, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("No text extracted")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if let timestamp = item.timestamp {
                    Text(timestamp, formatter: itemFormatter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
