//
//  HomeworkCaptureViewModel.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import Combine

/// View model that manages the state and business logic for capturing and processing homework images.
///
/// This view model handles:
/// - Image selection from camera or photo library
/// - OCR text extraction from images
/// - Saving homework items to Core Data
class HomeworkCaptureViewModel: ObservableObject {
    // MARK: - Published Properties

    /// The image selected from camera or photo library
    @Published var selectedImage: UIImage?

    /// Controls the visibility of the image picker sheet
    @Published var showImagePicker = false

    /// Determines whether to use camera or photo library
    @Published var imageSourceType: UIImagePickerController.SourceType = .camera

    /// Controls the visibility of the action sheet for choosing image source
    @Published var showActionSheet = false

    /// Stores the text extracted from the homework image via OCR
    @Published var extractedText: String = ""

    /// Indicates whether OCR processing is in progress
    @Published var isProcessingOCR = false

    /// Controls the visibility of the text extraction result sheet
    @Published var showTextSheet = false

    // MARK: - Private Properties

    /// The Core Data managed object context for database operations (used for initialization)
    private let initialContext: NSManagedObjectContext

    // MARK: - Initialization

    /// Initializes the view model with a Core Data managed object context.
    ///
    /// - Parameter context: The NSManagedObjectContext for database operations
    init(context: NSManagedObjectContext) {
        self.initialContext = context
    }

    // MARK: - Public Methods

    /// Presents the action sheet to choose between camera and photo library.
    func showImageSourceSelection() {
        showActionSheet = true
    }

    /// Selects the camera as the image source and presents the image picker.
    func selectCamera() {
        imageSourceType = .camera
        showImagePicker = true
    }

    /// Selects the photo library as the image source and presents the image picker.
    func selectPhotoLibrary() {
        imageSourceType = .photoLibrary
        showImagePicker = true
    }

    /// Performs OCR on the selected image and displays the results.
    ///
    /// This method:
    /// 1. Shows the text sheet with a progress indicator
    /// 2. Calls OCRService to extract text from the image
    /// 3. Updates the UI with extracted text or error message on completion
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    func performOCR(on image: UIImage) {
        isProcessingOCR = true
        showTextSheet = true
        extractedText = ""

        OCRService.shared.recognizeText(from: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isProcessingOCR = false
                switch result {
                case .success(let text):
                    self.extractedText = text
                case .failure(let error):
                    self.extractedText = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Saves the current homework item with extracted text to Core Data.
    ///
    /// This method creates a new Item entity with the current timestamp and
    /// saves it to the persistent store.
    ///
    /// - Parameter context: The NSManagedObjectContext to use for saving
    func saveHomework(context: NSManagedObjectContext) {
        withAnimation {
            let newItem = Item(context: context)
            newItem.timestamp = Date()
            // TODO: Add extracted text and image data to the item once model is updated

            do {
                try context.save()
                dismissTextSheet()
            } catch {
                let nsError = error as NSError
                print("Error saving homework: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Dismisses the text sheet and resets the state.
    func dismissTextSheet() {
        showTextSheet = false
        extractedText = ""
        selectedImage = nil
    }
}
