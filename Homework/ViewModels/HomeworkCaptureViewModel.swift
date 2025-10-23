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
    var ocrBlocks: [OCRService.OCRBlock] = []

    /// Stores the selected image for cloud analysis
    var currentImage: UIImage?

    /// Stores the AI analysis result
    var analysisResult: AnalysisResult?

    /// The item being re-analyzed (if any)
    @Published var reanalyzingItem: Item?

    /// The newly created homework item
    @Published var newlyCreatedItem: Item?

    // MARK: - Private Properties

    /// The Core Data managed object context for database operations (used for initialization)
    let initialContext: NSManagedObjectContext

    @AppStorage("useCloudAnalysis") var useCloudAnalysis = false
    
    // MARK: - Initialization
    
    /// Initializes the view model with a Core Data managed object context.
    ///
    /// - Parameter context: The NSManagedObjectContext for database operations
    init(context: NSManagedObjectContext) {
        self.initialContext = context
    }
}
