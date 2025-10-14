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

    /// Stores the text extracted from the homework image via OCR
    @Published var extractedText: String = ""

    /// Indicates whether OCR processing is in progress
    @Published var isProcessingOCR = false

    /// Controls the visibility of the text extraction result sheet
    @Published var showTextSheet = false

    /// Progress information for segment analysis
    @Published var analysisProgress: (current: Int, total: Int)? = nil

    /// Indicates whether cloud analysis is available/in progress
    @Published var isCloudAnalysisInProgress = false

    /// Stores the OCR blocks with position information for AI analysis
    private var ocrBlocks: [OCRService.OCRBlock] = []

    /// Stores the selected image for cloud analysis
    private var currentImage: UIImage?

    /// Stores the AI analysis result
    private var analysisResult: AIAnalysisService.AnalysisResult?

    /// The item being re-analyzed (if any)
    @Published var reanalyzingItem: Item?

    /// The newly created homework item
    @Published var newlyCreatedItem: Item?

    /// Controls the visibility of the cloud analysis alert
    @Published var showCloudAnalysisAlert = false

    // MARK: - Private Properties

    /// The Core Data managed object context for database operations (used for initialization)
    private let initialContext: NSManagedObjectContext

    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    // MARK: - Initialization

    /// Initializes the view model with a Core Data managed object context.
    ///
    /// - Parameter context: The NSManagedObjectContext for database operations
    init(context: NSManagedObjectContext) {
        self.initialContext = context
    }

    /// Creates a new homework item with a processing status.
    ///
    /// - Parameters:
    ///   - image: The homework image.
    ///   - context: The Core Data context.
    /// - Returns: The newly created homework item.
    func createHomeworkItem(from image: UIImage, context: NSManagedObjectContext) -> Item {
        let newItem = Item(context: context)
        newItem.timestamp = Date()
        newItem.imageData = image.jpegData(compressionQuality: 0.8)
        newItem.analysisJSON = "inProgress" // Set status to inProgress

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return newItem
    }

    // MARK: - Public Methods

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
        if !AIAnalysisService.shared.isModelAvailable && !useCloudAnalysis {
            self.showCloudAnalysisAlert = true
            return
        }

        let newItem = createHomeworkItem(from: image, context: initialContext)
        selectedImage = nil
        showImagePicker = false
        let useCloud = self.useCloudAnalysis || !AIAnalysisService.shared.isModelAvailable

        Task.detached(priority: .background) {
            do {
                let ocrResult = try await OCRService.shared.recognizeTextWithBlocks(from: image)
                let aiBlocks = ocrResult.blocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

                let analysisResult: Result<AIAnalysisService.AnalysisResult, Error>
                if useCloud {
                    analysisResult = await CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: aiBlocks)
                } else {
                    analysisResult = await AIAnalysisService.shared.analyzeHomeworkWithSegments(image: image, ocrBlocks: aiBlocks)
                }
                
                DispatchQueue.main.async {
                    switch analysisResult {
                    case .success(let analysis):
                        do {
                            let encoder = JSONEncoder()
                            let jsonData = try encoder.encode(analysis)
                            newItem.analysisJSON = String(data: jsonData, encoding: .utf8)
                        } catch {
                            newItem.analysisJSON = "failed"
                        }
                    case .failure:
                        newItem.analysisJSON = "failed"
                    }
                    
                    do {
                        try self.initialContext.save()
                    } catch {
                        print("Error saving context after analysis: \(error)")
                    }
                    
                    if case .success(let analysis) = analysisResult {
                        AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                            DispatchQueue.main.async {
                                switch summaryResult {
                                case .success(let summary):
                                    newItem.extractedText = summary
                                case .failure:
                                    newItem.extractedText = "Found \(analysis.exercises.count) exercise(s)."
                                }
                                
                                do {
                                    try self.initialContext.save()
                                } catch {
                                    print("Error saving context after summary generation: \(error)")
                                }
                            }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    newItem.analysisJSON = "failed"
                    do {
                        try self.initialContext.save()
                    } catch {
                        print("Error saving context after OCR failure: \(error)")
                    }
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

        // Use segment-based analysis with progress tracking
        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: aiBlocks,
            progressHandler: { [weak self] current, total in
                DispatchQueue.main.async {
                    self?.analysisProgress = (current, total)
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.analysisProgress = nil

                switch result {
                case .success(let analysis):
                    print("DEBUG VM: Received analysis - Exercises: \(analysis.exercises.count)")
                    self.analysisResult = analysis

                    // Generate a summary of the homework instead of showing raw OCR text
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary
                                print("DEBUG VM: Generated summary: \(summary)")

                            case .failure(let error):
                                print("DEBUG VM: Summary generation failed - \(error.localizedDescription)")
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    print("DEBUG VM: Analysis failed - \(error.localizedDescription)")
                    self.isProcessingOCR = false
                    // Continue with just OCR text if AI analysis fails
                    break
                }
            }
        }
    }

    /// Saves the current homework item with extracted text to Core Data.
    ///
    /// This method either creates a new Item entity or updates an existing one if in re-analysis mode.
    ///
    /// - Parameter context: The NSManagedObjectContext to use for saving
    func saveHomework(context: NSManagedObjectContext) {
        withAnimation {
            let item: Item

            // Check if we're re-analyzing an existing item
            if let existingItem = reanalyzingItem {
                item = existingItem
                print("DEBUG SAVE: ⚠️ OVERWRITING existing item analysis")
                if let oldAnalysis = item.analysisResult {
                    print("DEBUG SAVE: Previous analysis had \(oldAnalysis.exercises.count) exercises")
                }
            } else {
                item = Item(context: context)
                item.timestamp = Date()

                // Convert UIImage to JPEG data for storage (only for new items)
                if let image = selectedImage,
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    item.imageData = imageData
                }
                print("DEBUG SAVE: Creating new item")
            }

            // Update extracted text (summary)
            item.extractedText = extractedText

            // Save AI analysis result as JSON
            if let analysis = analysisResult {
                print("DEBUG SAVE: Saving analysis - Exercises: \(analysis.exercises.count)")
                print("DEBUG SAVE: Exercise order before encoding:")
                for (idx, ex) in analysis.exercises.enumerated() {
                    print("  Position \(idx): Exercise #\(ex.exerciseNumber), Y: \(ex.startY)-\(ex.endY)")
                    print("     Content preview: \(ex.fullContent.prefix(80))...")
                }
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let jsonData = try encoder.encode(analysis)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        // Explicitly overwrite analysisJSON field
                        item.analysisJSON = jsonString
                        print("DEBUG SAVE: ✅ Analysis JSON saved successfully (overwrites any previous analysis)")
                    }
                } catch {
                    print("❌ Error encoding analysis result: \(error)")
                }
            } else {
                print("DEBUG SAVE: No analysis result to save")
            }

            do {
                try context.save()
                print("DEBUG SAVE: ✅ Core Data save successful")
                dismissTextSheet()
            } catch {
                let nsError = error as NSError
                print("❌ Error saving homework: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    /// Dismisses the text sheet and resets the state.
    func dismissTextSheet() {
        showTextSheet = false
        extractedText = ""
        selectedImage = nil
        analysisProgress = nil
        currentImage = nil
        isCloudAnalysisInProgress = false
        reanalyzingItem = nil
    }

    /// Re-analyzes an existing homework item
    ///
    /// - Parameters:
    ///   - item: The homework item to re-analyze
    ///   - context: The Core Data context
    ///   - useCloud: Whether to use cloud analysis instead of local
    func reanalyzeHomework(item: Item, context: NSManagedObjectContext, useCloud: Bool = false) {
        // Load image from item
        guard let imageData = item.imageData,
              let image = UIImage(data: imageData) else {
            print("DEBUG REANALYZE: No image data found in item")
            return
        }

        reanalyzingItem = item
        isProcessingOCR = true
        showTextSheet = true
        extractedText = ""
        ocrBlocks = []
        analysisResult = nil
        analysisProgress = nil
        currentImage = image
        isCloudAnalysisInProgress = useCloud

        print("DEBUG REANALYZE: Starting re-analysis for item with timestamp: \(item.timestamp?.description ?? "none")")

        // Step 1: Perform OCR with block position information
        OCRService.shared.recognizeTextWithBlocks(from: image) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    self.ocrBlocks = ocrResult.blocks
                    print("DEBUG REANALYZE: OCR completed with \(ocrResult.blocks.count) blocks")
                }

                // Step 2: Perform AI analysis
                if useCloud {
                    self.performCloudAnalysisForReanalysis(image: image, ocrBlocks: ocrResult.blocks, item: item, context: context)
                } else {
                    self.analyzeHomeworkContentForReanalysis(image: image, ocrBlocks: ocrResult.blocks, item: item, context: context)
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isProcessingOCR = false
                    print("DEBUG REANALYZE: OCR Error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Analyzes homework content for re-analysis
    private func analyzeHomeworkContentForReanalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock], item: Item, context: NSManagedObjectContext) {
        // Convert OCRService.OCRBlock to AIAnalysisService.OCRBlock
        let aiBlocks = ocrBlocks.map { block in
            AIAnalysisService.OCRBlock(text: block.text, y: block.y)
        }

        // Use segment-based analysis with progress tracking
        AIAnalysisService.shared.analyzeHomeworkWithSegments(
            image: image,
            ocrBlocks: aiBlocks,
            progressHandler: { [weak self] current, total in
                DispatchQueue.main.async {
                    self?.analysisProgress = (current, total)
                }
            }
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.analysisProgress = nil

                switch result {
                case .success(let analysis):
                    print("DEBUG REANALYZE: Received analysis - Exercises: \(analysis.exercises.count)")
                    self.analysisResult = analysis

                    // Generate a summary of the homework
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary
                                print("DEBUG REANALYZE: Generated summary: \(summary)")
                                self.saveHomework(context: context)

                            case .failure(let error):
                                print("DEBUG REANALYZE: Summary generation failed - \(error.localizedDescription)")
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    print("DEBUG REANALYZE: Analysis failed - \(error.localizedDescription)")
                    self.isProcessingOCR = false
                }
            }
        }
    }

    /// Performs cloud analysis for re-analysis
    private func performCloudAnalysisForReanalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock], item: Item, context: NSManagedObjectContext) {
        DispatchQueue.main.async {
            self.isCloudAnalysisInProgress = true
        }

        // Convert OCR blocks to AI service format
        let aiBlocks = ocrBlocks.map { block in
            AIAnalysisService.OCRBlock(text: block.text, y: block.y)
        }

        print("DEBUG REANALYZE CLOUD: Starting cloud analysis with \(aiBlocks.count) OCR blocks")

        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: aiBlocks
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isCloudAnalysisInProgress = false

                switch result {
                case .success(let analysis):
                    print("DEBUG REANALYZE CLOUD: Cloud analysis successful - Exercises: \(analysis.exercises.count)")
                    self.analysisResult = analysis

                    // Generate a summary for cloud analysis results
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary
                                print("DEBUG REANALYZE CLOUD: Generated summary: \(summary)")
                                self.saveHomework(context: context)

                            case .failure(let error):
                                print("DEBUG REANALYZE CLOUD: Summary generation failed - \(error.localizedDescription)")
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    print("DEBUG REANALYZE CLOUD: Cloud analysis failed - \(error.localizedDescription)")
                    self.isProcessingOCR = false
                }
            }
        }
    }

    /// Performs cloud-based analysis using Firebase Functions
    func performCloudAnalysis() {
        guard let image = currentImage, !ocrBlocks.isEmpty else {
            print("DEBUG CLOUD: No image or OCR blocks available for cloud analysis")
            return
        }

        DispatchQueue.main.async {
            self.isCloudAnalysisInProgress = true
        }

        // Convert OCR blocks to AI service format
        let aiBlocks = ocrBlocks.map { block in
            AIAnalysisService.OCRBlock(text: block.text, y: block.y)
        }

        print("DEBUG CLOUD: Starting cloud analysis with \(aiBlocks.count) OCR blocks")

        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: aiBlocks
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isCloudAnalysisInProgress = false

                switch result {
                case .success(let analysis):
                    print("DEBUG CLOUD: Cloud analysis successful - Exercises: \(analysis.exercises.count)")
                    self.analysisResult = analysis

                    // Generate a summary for cloud analysis results
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary
                                print("DEBUG CLOUD: Generated summary: \(summary)")

                            case .failure(let error):
                                print("DEBUG CLOUD: Summary generation failed - \(error.localizedDescription)")
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    print("DEBUG CLOUD: Cloud analysis failed - \(error.localizedDescription)")
                    // Show error to user (you can add an alert here)
                }
            }
        }
    }
}

