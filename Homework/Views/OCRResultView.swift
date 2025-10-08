//
//  OCRResultView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI

/// A view that displays the results of OCR text extraction with save/cancel actions.
///
/// This view shows either a progress indicator during OCR processing or the
/// extracted text once processing is complete. Users can save the results or cancel.
struct OCRResultView: View {
    // MARK: - Properties

    /// The extracted text to display
    let extractedText: String

    /// Indicates whether OCR processing is currently in progress
    let isProcessing: Bool

    /// Callback triggered when the user taps the Save button
    var onSave: () -> Void

    /// Callback triggered when the user taps the Cancel button
    var onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack {
                if isProcessing {
                    OCRLoadingView()
                } else {
                    OCRTextContentView(text: extractedText)
                }
            }
            .navigationTitle("Extracted Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GlassmorphicButtonStyle())
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save", action: onSave)
                        .disabled(extractedText.isEmpty)
                        .buttonStyle(GlassmorphicButtonStyle())
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.15),
                        Color(red: 0.15, green: 0.15, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// A view showing a progress indicator during OCR processing.
private struct OCRLoadingView: View {
    var body: some View {
        ProgressView("Extracting text...")
            .padding()
    }
}

/// A view displaying the extracted text in a scrollable area.
private struct OCRTextContentView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Previews

#Preview("Processing") {
    OCRResultView(
        extractedText: "",
        isProcessing: true,
        onSave: {},
        onCancel: {}
    )
}

#Preview("Completed") {
    OCRResultView(
        extractedText: "Sample homework text\nLine 2\nLine 3",
        isProcessing: false,
        onSave: {},
        onCancel: {}
    )
}
