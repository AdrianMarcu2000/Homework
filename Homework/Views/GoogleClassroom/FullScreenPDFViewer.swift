
//
//  FullScreenPDFViewer.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import PDFKit

// MARK: - Full Screen PDF Viewer

struct FullScreenPDFViewer: View {
    let pdfData: Data
    let title: String

    var body: some View {
        if let pdfDocument = PDFDocument(data: pdfData) {
            PDFKitViewFullScreen(document: pdfDocument)
                .edgesIgnoringSafeArea(.all)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Failed to load PDF")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding()
        }
    }
}

struct PDFKitViewFullScreen: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .black
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
