
//
//  HomeworkCaptureViewModel+PDF.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import PDFKit
import OSLog

extension HomeworkCaptureViewModel {
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
    func performPDFAnalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
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
                    let singleExercise = Exercise(
                        exerciseNumber: "1",
                        type: "other",
                        fullContent: fullText,
                        startY: 0.0,
                        endY: 1.0,
                        subject: "General",
                        inputType: "text"
                    )

                    let ocrOnlyAnalysis = AnalysisResult(
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
            let aiBlocks = ocrBlocks.map { OCRBlock(text: $0.text, y: $0.y) }

            let analysisResult: Result<AnalysisResult, Error>
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
}
