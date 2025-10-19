//
//  DocumentPicker.swift
//  Homework
//
//  Created by Claude on 16.10.2025.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OSLog

/// A SwiftUI wrapper for UIDocumentPickerViewController that allows users to select image files
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Allow only image types
        let supportedTypes: [UTType] = [.image, .png, .jpeg, .heic]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            // Access the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                AppLogger.ui.error("Failed to access security-scoped resource")
                parent.presentationMode.wrappedValue.dismiss()
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            // Load the image from the URL
            do {
                let imageData = try Data(contentsOf: url)
                if let image = UIImage(data: imageData) {
                    parent.selectedImage = image
                    AppLogger.ui.info("Loaded image from file: \(url.lastPathComponent)")
                } else {
                    AppLogger.ui.error("Failed to create UIImage from file data")
                }
            } catch {
                AppLogger.ui.error("Error loading image from file", error: error)
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
