
//
//  ODTDetailViewer.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

/// ODT viewer for detail pane
struct ODTDetailViewer: View {
    let odtData: Data
    let fileName: String
    @State private var content: ODTProcessingService.ODTContent?
    @State private var isProcessing = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Processing ODT document...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Failed to load ODT")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if let content = content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display extracted text
                        if !content.text.isEmpty {
                            Text(content.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                        }

                        // Display extracted images
                        if !content.images.isEmpty {
                            ForEach(Array(content.images.enumerated()), id: \.offset) { index, image in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Image \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)

                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Empty document")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            processODT()
        }
    }

    private func processODT() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let extractedContent = ODTProcessingService.shared.extractContent(from: odtData) {
                DispatchQueue.main.async {
                    content = extractedContent
                    isProcessing = false
                    AppLogger.image.info("ODT processed: \(extractedContent.text.count) chars, \(extractedContent.images.count) images")
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Could not extract content from ODT file"
                    isProcessing = false
                    AppLogger.image.error("Failed to process ODT document")
                }
            }
        }
    }
}
