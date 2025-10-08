//
//  ImagePicker.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import UIKit

/// A SwiftUI wrapper for UIImagePickerController that allows users to select images
/// from either the camera or photo library.
///
/// This view conforms to UIViewControllerRepresentable to bridge UIKit's
/// UIImagePickerController into SwiftUI.
///
/// Example usage:
/// ```swift
/// @State private var selectedImage: UIImage?
/// @State private var showPicker = false
///
/// .sheet(isPresented: $showPicker) {
///     ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
/// }
/// ```
struct ImagePicker: UIViewControllerRepresentable {
    /// Environment value to dismiss the picker view
    @Environment(\.presentationMode) var presentationMode

    /// Binding to store the selected image
    @Binding var selectedImage: UIImage?

    /// The source type for the image picker (camera or photo library)
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Coordinator that acts as the delegate for UIImagePickerController
    /// to handle image selection and cancellation events.
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        /// Called when the user selects an image
        /// - Parameters:
        ///   - picker: The image picker controller
        ///   - info: Dictionary containing the selected media information
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        /// Called when the user cancels the image picker
        /// - Parameter picker: The image picker controller
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
