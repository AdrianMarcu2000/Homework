
//
//  ODTViewerContent.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

struct ODTViewerContent: View {
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
