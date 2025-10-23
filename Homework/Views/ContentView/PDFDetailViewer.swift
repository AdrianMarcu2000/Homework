
//
//  PDFDetailViewer.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import PDFKit
import OSLog

/// PDF viewer for detail pane
struct PDFDetailViewer: View {
    let pdfData: Data

    var body: some View {
        let _ = AppLogger.image.info("PDFDetailViewer: Attempting to load PDF with \(pdfData.count) bytes")

        if let pdfDocument = PDFDocument(data: pdfData) {
            let _ = AppLogger.image.info("PDFDetailViewer: PDF loaded successfully, page count: \(pdfDocument.pageCount)")
            PDFKitDetailView(document: pdfDocument)
        } else {
            let _ = AppLogger.image.error("PDFDetailViewer: Failed to create PDFDocument from data")

            // Log data preview for debugging
            let previewLength = min(16, pdfData.count)
            let preview = pdfData.prefix(previewLength).map { String(format: "%02x", $0) }.joined(separator: " ")
            let _ = AppLogger.image.info("PDF data preview (first \(previewLength) bytes): \(preview)")

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Failed to load PDF")
                    .font(.headline)
                Text("\(pdfData.count) bytes received")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

private struct PDFKitDetailView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
