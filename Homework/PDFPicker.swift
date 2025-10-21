//
//  PDFPicker.swift
//  Homework
//
//  A SwiftUI wrapper for UIDocumentPickerViewController that allows users to select PDF files
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OSLog

/// A SwiftUI wrapper for UIDocumentPickerViewController to select PDF files
struct PDFPicker: UIViewControllerRepresentable {
    /// Environment value to dismiss the picker view
    @Environment(\.presentationMode) var presentationMode

    /// Binding to store the selected PDF data
    @Binding var selectedPDFData: Data?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        AppLogger.ui.info("Presenting PDF document picker")

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Coordinator that acts as the delegate for UIDocumentPickerViewController
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PDFPicker

        init(_ parent: PDFPicker) {
            self.parent = parent
        }

        /// Called when the user selects a PDF document
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                AppLogger.ui.warning("No URL selected from document picker")
                parent.presentationMode.wrappedValue.dismiss()
                return
            }

            AppLogger.ui.info("User selected PDF: \(url.lastPathComponent)")

            // Access security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                AppLogger.ui.error("Failed to access security-scoped resource: \(url.path)")
                parent.presentationMode.wrappedValue.dismiss()
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            do {
                let pdfData = try Data(contentsOf: url)
                AppLogger.ui.info("Loaded PDF data: \(pdfData.count) bytes")
                parent.selectedPDFData = pdfData
            } catch {
                AppLogger.ui.error("Failed to load PDF data", error: error)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        /// Called when the user cancels the document picker
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            AppLogger.ui.info("User cancelled PDF picker")
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
