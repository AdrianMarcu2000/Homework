//
//  HomeworkCaptureViewModel.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import Combine
import PDFKit
import OSLog

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

    /// Controls the visibility of the document picker sheet
    @Published var showDocumentPicker = false

    /// Controls the visibility of the PDF picker sheet
    @Published var showPDFPicker = false

    /// Stores the selected PDF data
    @Published var selectedPDFData: Data?

    /// Stores the extracted pages from the PDF
    @Published var pdfPages: [PDFService.PDFPageData] = []

    /// Controls the visibility of the PDF page selector sheet
    @Published var showPDFPageSelector = false

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
        AppLogger.ui.info("User selected camera for homework capture")
        imageSourceType = .camera
        showImagePicker = true
    }

    /// Selects the photo library as the image source and presents the image picker.
    func selectPhotoLibrary() {
        AppLogger.ui.info("User selected photo library for homework capture")
        imageSourceType = .photoLibrary
        showImagePicker = true
    }

    /// Presents the document picker to allow users to select image files from the Files app.
    func selectDocumentPicker() {
        AppLogger.ui.info("User opened document picker for homework selection")
        showDocumentPicker = true
    }

    /// Presents the PDF picker to allow users to select PDF files.
    func selectPDFPicker() {
        AppLogger.ui.info("User opened PDF picker for homework selection")
        showPDFPicker = true
    }

    /// Processes the selected PDF by saving it to storage and creating a homework item
    func processPDF() {
        guard let pdfData = selectedPDFData else {
            AppLogger.image.warning("No PDF data available to process")
            return
        }

        AppLogger.image.info("Processing selected PDF (\(pdfData.count) bytes)")

        Task.detached(priority: .background) {
            do {
                // Save PDF to app storage
                let relativePath = try await PDFStorageService.shared.savePDF(data: pdfData)

                // Create homework item with PDF reference
                await MainActor.run {
                    let newItem = Item(context: self.initialContext)
                    newItem.timestamp = Date()
                    newItem.pdfFilePath = relativePath

                    // Set a title based on file
                    newItem.extractedText = "PDF Homework"

                    do {
                        try self.initialContext.save()
                        AppLogger.persistence.info("Saved PDF homework item with path: \(relativePath)")

                        // Clear the selected PDF data
                        self.selectedPDFData = nil
                        self.showPDFPicker = false

                        // Set as newly created item so it's selected
                        self.newlyCreatedItem = newItem
                    } catch {
                        AppLogger.persistence.error("Failed to save PDF homework item", error: error)
                    }
                }
            } catch {
                await AppLogger.image.error("Failed to save PDF to storage", error: error)
            }
        }
    }

    /// Processes a selected PDF page for homework analysis
    /// - Parameter pageData: The PDF page data to analyze
    func processPDFPage(_ pageData: PDFService.PDFPageData) {
        AppLogger.ui.info("User selected PDF page \(pageData.pageNumber) for analysis")

        let image = pageData.pageImage

        // Check if page has native text or needs OCR
        if pageData.hasNativeText, let extractedText = pageData.extractedText {
            AppLogger.image.info("Using native PDF text (\(extractedText.count) characters)")

            // Create OCR blocks from native text
            // For native text PDFs, we'll create a single block spanning the full page
            let ocrBlocks = [OCRService.OCRBlock(text: extractedText, y: 0.5)]

            // Now proceed with analysis using the image and text
            performPDFAnalysis(image: image, ocrBlocks: ocrBlocks)
        } else {
            AppLogger.image.info("PDF page requires OCR processing")

            // Perform OCR on the PDF page image
            performOCR(on: image)
        }

        // Close the PDF page selector
        DispatchQueue.main.async {
            self.showPDFPageSelector = false
            self.pdfPages = []
            self.selectedPDFData = nil
        }
    }

    /// Performs analysis on a PDF page with extracted text
    private func performPDFAnalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
        let newItem = createHomeworkItem(from: image, context: initialContext)

        // Determine if we should use AI analysis
        let shouldUseAI = AIAnalysisService.shared.isModelAvailable || useCloudAnalysis
        let useCloud = self.useCloudAnalysis || !AIAnalysisService.shared.isModelAvailable

        Task.detached(priority: .background) {
            // If no AI is available, create a single exercise from OCR text
            if !shouldUseAI {
                await MainActor.run {
                    let fullText = ocrBlocks.map { $0.text }.joined(separator: "\n")
                    newItem.extractedText = fullText
                    newItem.analysisMethod = AnalysisMethod.ocrOnly.rawValue

                    // Create a single exercise containing all OCR text
                    let singleExercise = AIAnalysisService.Exercise(
                        exerciseNumber: "1",
                        type: "other",
                        fullContent: fullText,
                        startY: 0.0,
                        endY: 1.0,
                        subject: "General",
                        inputType: "text"
                    )

                    let ocrOnlyAnalysis = AIAnalysisService.AnalysisResult(
                        exercises: [singleExercise]
                    )

                    // Save as JSON
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(ocrOnlyAnalysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            newItem.analysisJSON = jsonString
                        }
                        try self.initialContext.save()
                        AppLogger.ocr.info("PDF OCR-only processing complete")
                    } catch {
                        AppLogger.persistence.error("Failed to save context after PDF OCR", error: error)
                    }
                }
                return
            }

            // Perform AI analysis
            let aiBlocks = ocrBlocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

            let analysisResult: Result<AIAnalysisService.AnalysisResult, Error>
            if useCloud {
                analysisResult = await CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: aiBlocks)
            } else {
                analysisResult = await AIAnalysisService.shared.analyzeHomeworkWithSegments(image: image, ocrBlocks: aiBlocks)
            }

            await MainActor.run {
                switch analysisResult {
                case .success(let analysis):
                    do {
                        let encoder = JSONEncoder()
                        let jsonData = try encoder.encode(analysis)
                        newItem.analysisJSON = String(data: jsonData, encoding: .utf8)
                        newItem.analysisMethod = useCloud ? AnalysisMethod.cloudAI.rawValue : AnalysisMethod.appleAI.rawValue
                    } catch {
                        AppLogger.ai.error("Failed to encode PDF analysis result", error: error)
                        newItem.analysisJSON = "failed"
                    }
                case .failure(let error):
                    AppLogger.ai.error("PDF AI analysis failed", error: error)
                    newItem.analysisJSON = "failed"
                }

                do {
                    try self.initialContext.save()
                    AppLogger.persistence.info("PDF homework item saved after analysis")
                } catch {
                    AppLogger.persistence.error("Failed to save context after PDF analysis", error: error)
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
                                AppLogger.persistence.info("PDF summary saved to homework item")
                            } catch {
                                AppLogger.persistence.error("Failed to save context after PDF summary", error: error)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Performs OCR on the selected image and displays the results.
    ///
    /// This method:
    /// 1. Shows the text sheet with a progress indicator
    /// 2. Calls OCRService to extract text and position blocks from the image
    /// 3. Performs AI analysis to segment lessons and exercises (if available)
    /// 4. Updates the UI with extracted text or error message on completion
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    func performOCR(on image: UIImage) {
        let newItem = createHomeworkItem(from: image, context: initialContext)
        selectedImage = nil
        showImagePicker = false

        // Determine if we should use AI analysis
        let shouldUseAI = AIAnalysisService.shared.isModelAvailable || useCloudAnalysis
        let useCloud = self.useCloudAnalysis || !AIAnalysisService.shared.isModelAvailable

        Task.detached(priority: .background) {
            do {
                let ocrResult = try await OCRService.shared.recognizeTextWithBlocks(from: image)

                // If no AI is available, create a single exercise from OCR text
                if !shouldUseAI {
                    await MainActor.run {
                        newItem.extractedText = ocrResult.fullText
                        newItem.analysisMethod = AnalysisMethod.ocrOnly.rawValue

                        // Create a single exercise containing all OCR text
                        let singleExercise = AIAnalysisService.Exercise(
                            exerciseNumber: "1",
                            type: "other",
                            fullContent: ocrResult.fullText,
                            startY: 0.0,
                            endY: 1.0,
                            subject: "General",
                            inputType: "text"
                        )

                        let ocrOnlyAnalysis = AIAnalysisService.AnalysisResult(
                            exercises: [singleExercise]
                        )

                        // Save as JSON
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            let jsonData = try encoder.encode(ocrOnlyAnalysis)
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                newItem.analysisJSON = jsonString
                            }
                            try self.initialContext.save()
                            AppLogger.ocr.info("OCR-only processing complete, created single exercise")
                        } catch {
                            AppLogger.persistence.error("Failed to save context after OCR", error: error)
                        }
                    }
                    return
                }

                // Perform AI analysis
                let aiBlocks = ocrResult.blocks.map { AIAnalysisService.OCRBlock(text: $0.text, y: $0.y) }

                let analysisResult: Result<AIAnalysisService.AnalysisResult, Error>
                if useCloud {
                    analysisResult = await CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: aiBlocks)
                } else {
                    analysisResult = await AIAnalysisService.shared.analyzeHomeworkWithSegments(image: image, ocrBlocks: aiBlocks)
                }

                await MainActor.run {
                    switch analysisResult {
                    case .success(let analysis):
                        do {
                            let encoder = JSONEncoder()
                            let jsonData = try encoder.encode(analysis)
                            newItem.analysisJSON = String(data: jsonData, encoding: .utf8)
                            // Set the analysis method based on which service was used
                            newItem.analysisMethod = useCloud ? AnalysisMethod.cloudAI.rawValue : AnalysisMethod.appleAI.rawValue
                        } catch {
                            AppLogger.ai.error("Failed to encode analysis result", error: error)
                            newItem.analysisJSON = "failed"
                        }
                    case .failure(let error):
                        AppLogger.ai.error("AI analysis failed", error: error)
                        newItem.analysisJSON = "failed"
                    }

                    do {
                        try self.initialContext.save()
                        AppLogger.persistence.info("Homework item saved after analysis")
                    } catch {
                        AppLogger.persistence.error("Failed to save context after analysis", error: error)
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
                                    AppLogger.persistence.info("Summary saved to homework item")
                                } catch {
                                    AppLogger.persistence.error("Failed to save context after summary generation", error: error)
                                }
                            }
                        }
                    }
                }
            } catch {
                await AppLogger.ocr.error("OCR processing failed", error: error)
                await MainActor.run {
                    newItem.analysisJSON = "failed"
                    do {
                        try self.initialContext.save()
                    } catch {
                        AppLogger.persistence.error("Failed to save context after OCR failure", error: error)
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
                    AppLogger.ai.info("Received analysis with \(analysis.exercises.count) exercises")
                    self.analysisResult = analysis

                    // Generate a summary of the homework instead of showing raw OCR text
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary

                            case .failure(let error):
                                AppLogger.ai.error("Summary generation failed", error: error)
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    AppLogger.ai.error("AI analysis failed", error: error)
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
                AppLogger.persistence.info("Overwriting existing item analysis")
            } else {
                item = Item(context: context)
                item.timestamp = Date()

                // Convert UIImage to JPEG data for storage (only for new items)
                if let image = selectedImage,
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    item.imageData = imageData
                }
                AppLogger.persistence.info("Creating new homework item")
            }

            // Update extracted text (summary)
            item.extractedText = extractedText

            // Save AI analysis result as JSON
            if let analysis = analysisResult {
                AppLogger.persistence.info("Saving analysis with \(analysis.exercises.count) exercises")
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let jsonData = try encoder.encode(analysis)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        // Explicitly overwrite analysisJSON field
                        item.analysisJSON = jsonString
                        // Set analysis method based on whether cloud was used
                        item.analysisMethod = isCloudAnalysisInProgress ? AnalysisMethod.cloudAI.rawValue : AnalysisMethod.appleAI.rawValue
                        AppLogger.persistence.info("Analysis JSON saved successfully")
                    }
                } catch {
                    AppLogger.persistence.error("Failed to encode analysis result", error: error)
                }
            }

            do {
                try context.save()
                AppLogger.persistence.info("Core Data save successful")
                dismissTextSheet()
            } catch {
                AppLogger.persistence.error("Failed to save homework", error: error)
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
            AppLogger.ui.error("No image data found in item for reanalysis", error: NSError(domain: "HomeworkCapture", code: -1))
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

        AppLogger.ui.info("Starting homework reanalysis with \(useCloud ? "cloud" : "local") AI")

        // Check if AI analysis is available
        let shouldUseAI = AIAnalysisService.shared.isModelAvailable || useCloudAnalysis

        // Step 1: Perform OCR with block position information
        OCRService.shared.recognizeTextWithBlocks(from: image) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let ocrResult):
                DispatchQueue.main.async {
                    self.ocrBlocks = ocrResult.blocks
                    AppLogger.ocr.info("OCR completed with \(ocrResult.blocks.count) blocks for reanalysis")
                }

                // If no AI available, create single exercise from OCR text
                if !shouldUseAI {
                    DispatchQueue.main.async {
                        self.isProcessingOCR = false
                        item.extractedText = ocrResult.fullText
                        item.analysisMethod = AnalysisMethod.ocrOnly.rawValue

                        // Create a single exercise containing all OCR text
                        let singleExercise = AIAnalysisService.Exercise(
                            exerciseNumber: "1",
                            type: "other",
                            fullContent: ocrResult.fullText,
                            startY: 0.0,
                            endY: 1.0,
                            subject: "General",
                            inputType: "text"
                        )

                        let ocrOnlyAnalysis = AIAnalysisService.AnalysisResult(
                            exercises: [singleExercise]
                        )

                        // Save as JSON
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            let jsonData = try encoder.encode(ocrOnlyAnalysis)
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                item.analysisJSON = jsonString
                            }
                            try context.save()
                            AppLogger.ocr.info("OCR-only reanalysis complete, created single exercise")
                        } catch {
                            AppLogger.persistence.error("Failed to save OCR-only reanalysis", error: error)
                        }

                        self.reanalyzingItem = nil
                    }
                    return
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
                    AppLogger.ocr.error("OCR failed during reanalysis", error: error)
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
                    AppLogger.ai.info("Received reanalysis with \(analysis.exercises.count) exercises")
                    self.analysisResult = analysis

                    // Save analysis immediately
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(analysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            item.analysisJSON = jsonString
                            item.analysisMethod = AnalysisMethod.appleAI.rawValue
                            AppLogger.persistence.info("Analysis JSON saved to item")
                        }
                    } catch {
                        AppLogger.persistence.error("Failed to encode reanalysis result", error: error)
                    }

                    // Generate a summary of the homework
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                item.extractedText = summary

                            case .failure(let error):
                                AppLogger.ai.error("Summary generation failed during reanalysis", error: error)
                                // Fallback to a basic summary
                                item.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }

                            // Save to Core Data and force refresh
                            do {
                                try context.save()
                                // Force Core Data to refresh the object
                                context.refresh(item, mergeChanges: true)
                                AppLogger.persistence.info("Core Data saved and refreshed after reanalysis")
                            } catch {
                                AppLogger.persistence.error("Failed to save reanalysis", error: error)
                            }

                            self.reanalyzingItem = nil
                        }
                    }

                case .failure(let error):
                    AppLogger.ai.error("Reanalysis failed", error: error)
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

        AppLogger.cloud.info("Starting cloud reanalysis with \(aiBlocks.count) OCR blocks")

        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: aiBlocks
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isCloudAnalysisInProgress = false

                switch result {
                case .success(let analysis):
                    AppLogger.cloud.info("Cloud reanalysis successful with \(analysis.exercises.count) exercises")
                    self.analysisResult = analysis

                    // Save analysis immediately
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(analysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            item.analysisJSON = jsonString
                            item.analysisMethod = AnalysisMethod.cloudAI.rawValue
                            AppLogger.persistence.info("Cloud analysis JSON saved to item")
                        }
                    } catch {
                        AppLogger.persistence.error("Failed to encode cloud reanalysis result", error: error)
                    }

                    // Generate a summary for cloud analysis results
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            self.isProcessingOCR = false

                            switch summaryResult {
                            case .success(let summary):
                                item.extractedText = summary

                            case .failure(let error):
                                AppLogger.ai.error("Summary generation failed for cloud reanalysis", error: error)
                                // Fallback to a basic summary
                                item.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }

                            // Save to Core Data and force refresh
                            do {
                                try context.save()
                                // Force Core Data to refresh the object
                                context.refresh(item, mergeChanges: true)
                                AppLogger.persistence.info("Core Data saved and refreshed after cloud reanalysis")
                            } catch {
                                AppLogger.persistence.error("Failed to save cloud reanalysis", error: error)
                            }

                            self.reanalyzingItem = nil
                        }
                    }

                case .failure(let error):
                    AppLogger.cloud.error("Cloud reanalysis failed", error: error)
                    self.isProcessingOCR = false
                }
            }
        }
    }

    /// Performs cloud-based analysis using Firebase Functions
    func performCloudAnalysis() {
        guard let image = currentImage, !ocrBlocks.isEmpty else {
            AppLogger.cloud.error("No image or OCR blocks available for cloud analysis", error: NSError(domain: "HomeworkCapture", code: -1))
            return
        }

        DispatchQueue.main.async {
            self.isCloudAnalysisInProgress = true
        }

        // Convert OCR blocks to AI service format
        let aiBlocks = ocrBlocks.map { block in
            AIAnalysisService.OCRBlock(text: block.text, y: block.y)
        }

        AppLogger.cloud.info("Starting cloud analysis with \(aiBlocks.count) OCR blocks")

        CloudAnalysisService.shared.analyzeHomework(
            image: image,
            ocrBlocks: aiBlocks
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isCloudAnalysisInProgress = false

                switch result {
                case .success(let analysis):
                    AppLogger.cloud.info("Cloud analysis successful with \(analysis.exercises.count) exercises")
                    self.analysisResult = analysis

                    // Generate a summary for cloud analysis results
                    AIAnalysisService.shared.generateHomeworkSummary(for: analysis) { summaryResult in
                        DispatchQueue.main.async {
                            switch summaryResult {
                            case .success(let summary):
                                self.extractedText = summary

                            case .failure(let error):
                                AppLogger.ai.error("Summary generation failed for cloud analysis", error: error)
                                // Fallback to a basic summary
                                self.extractedText = "Found \(analysis.exercises.count) exercise(s) in this homework."
                            }
                        }
                    }

                case .failure(let error):
                    AppLogger.cloud.error("Cloud analysis failed", error: error)
                }
            }
        }
    }
}

