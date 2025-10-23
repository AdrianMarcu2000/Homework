
//
//  HomeworkTextView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// A simple view to display the homework original text
struct HomeworkTextView: View {
    let item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Show extracted text if available
                if let extractedText = item.extractedText, !extractedText.isEmpty {
                    Text(extractedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Text Available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Original")
        .navigationBarTitleDisplayMode(.inline)
    }
}
