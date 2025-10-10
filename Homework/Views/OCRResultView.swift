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

    /// Progress information (current segment, total segments)
    let analysisProgress: (current: Int, total: Int)?

    /// Indicates whether cloud analysis is in progress
    let isCloudAnalysisInProgress: Bool

    /// Callback triggered when the user taps the Save button
    var onSave: () -> Void

    /// Callback triggered when the user taps the Cancel button
    var onCancel: () -> Void

    /// Callback triggered when the user taps the Cloud Analysis button
    var onCloudAnalysis: (() -> Void)?

    /// User setting for cloud analysis
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack {
                if isProcessing {
                    OCRLoadingView(progress: analysisProgress)
                } else {
                    OCRTextContentView(text: extractedText)
                }
            }
            .navigationTitle(isProcessing || isCloudAnalysisInProgress ? "Analyzing Image" : "Homework Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .disabled(isCloudAnalysisInProgress)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Cloud Analysis button (only show when cloud analysis is enabled in settings)
                        if useCloudAnalysis && !isProcessing && !extractedText.isEmpty, let cloudAction = onCloudAnalysis {
                            Button(action: cloudAction) {
                                HStack(spacing: 4) {
                                    if isCloudAnalysisInProgress {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "cloud.fill")
                                    }
                                    Text(isCloudAnalysisInProgress ? "Analyzing..." : "Cloud AI")
                                }
                                .font(.subheadline)
                            }
                            .disabled(isCloudAnalysisInProgress)
                        }

                        Button("Save", action: onSave)
                            .disabled(isProcessing || extractedText.isEmpty || isCloudAnalysisInProgress)
                    }
                }
            }
        }
    }
}

/// A view showing a progress indicator during image analysis.
private struct OCRLoadingView: View {
    let progress: (current: Int, total: Int)?

    var body: some View {
        VStack(spacing: 20) {
            if let progress = progress {
                // Determinate progress with segment info
                VStack(spacing: 12) {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)

                    Text("Analyzing segment \(progress.current) of \(progress.total)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                // Indeterminate progress
                ProgressView("Analyzing image...")
            }
        }
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

#Preview("Processing - Initial") {
    OCRResultView(
        extractedText: "",
        isProcessing: true,
        analysisProgress: nil,
        isCloudAnalysisInProgress: false,
        onSave: {},
        onCancel: {},
        onCloudAnalysis: {}
    )
}

#Preview("Processing - With Progress") {
    OCRResultView(
        extractedText: "",
        isProcessing: true,
        analysisProgress: (current: 3, total: 7),
        isCloudAnalysisInProgress: false,
        onSave: {},
        onCancel: {},
        onCloudAnalysis: {}
    )
}

#Preview("Completed") {
    OCRResultView(
        extractedText: "Sample homework text\nLine 2\nLine 3",
        isProcessing: false,
        analysisProgress: nil,
        isCloudAnalysisInProgress: false,
        onSave: {},
        onCancel: {},
        onCloudAnalysis: {}
    )
}

#Preview("Cloud Analysis") {
    OCRResultView(
        extractedText: "Sample homework text\nLine 2\nLine 3",
        isProcessing: false,
        analysisProgress: nil,
        isCloudAnalysisInProgress: true,
        onSave: {},
        onCancel: {},
        onCloudAnalysis: {}
    )
}
