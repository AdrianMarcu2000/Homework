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

    /// Stores the OCR blocks with position information for AI analysis
    private var ocrBlocks: [OCRService.OCRBlock] = []

    /// Stores the AI analysis result
    private var analysisResult: AIAnalysisService.AnalysisResult?

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
    /// 2. Calls OCRService to extract text and position blocks from the image
    /// 3. Performs AI analysis to segment lessons and exercises
    /// 4. Updates the UI with extracted text or error message on completion
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    func performOCR(on image: UIImage) {
        isProcessingOCR = true
        showTextSheet = true
        extractedText = ""
        ocrBlocks = []
        analysisResult = nil

        // Step 1: Perform OCR with block position information
        OCRService.shared.recognizeTextWithBlocks(from: image) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    self.extractedText = ocrResult.fullText
                    self.ocrBlocks = ocrResult.blocks
                }

                // Step 2: Perform AI analysis to segment the content
                self.analyzeHomeworkContent(image: image, ocrBlocks: ocrResult.blocks)

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isProcessingOCR = false
                    self.extractedText = "OCR Error: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Analyzes homework content to identify lessons and exercises using AI
    ///
    /// - Parameters:
    ///   - image: The homework image
    ///   - ocrBlocks: OCR text blocks with position information
    private func analyzeHomeworkContent(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
        // Convert OCRService.OCRBlock to AIAnalysisService.OCRBlock
        let aiBlocks = ocrBlocks.map { block in
            AIAnalysisService.OCRBlock(text: block.text, y: block.y)
        }

        AIAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: aiBlocks
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isProcessingOCR = false

                switch result {
                case .success(let analysis):
                    self.analysisResult = analysis

                case .failure:
                    print ("Problem")
                    // Continue with just OCR text if AI analysis fails
                }
            }
        }
    }

    /// Saves the current homework item with extracted text to Core Data.
    ///
    /// This method creates a new Item entity with the current timestamp,
    /// extracted text, image data, and AI analysis results, then saves it to the persistent store.
    ///
    /// - Parameter context: The NSManagedObjectContext to use for saving
    func saveHomework(context: NSManagedObjectContext) {
        withAnimation {
            let newItem = Item(context: context)
            newItem.timestamp = Date()
            newItem.extractedText = extractedText

            // Convert UIImage to JPEG data for storage
            if let image = selectedImage,
               let imageData = image.jpegData(compressionQuality: 0.8) {
                newItem.imageData = imageData
            }

            // Save AI analysis result as JSON
            if let analysis = analysisResult {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let jsonData = try encoder.encode(analysis)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        newItem.analysis = jsonString
                    }
                } catch {
                    print("Error encoding analysis result: \(error)")
                }
            }

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
