
//
//  HomeworkCaptureViewModel+Analysis.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

extension HomeworkCaptureViewModel {
    /// Analyzes homework content to identify lessons and exercises using AI
    ///
    /// - Parameters:
    ///   - image: The homework image
    ///   - ocrBlocks: OCR text blocks with position information
    func analyzeHomeworkContent(image: UIImage, ocrBlocks: [OCRService.OCRBlock]) {
        // Convert OCRService.OCRBlock to OCRBlock
        let aiBlocks = ocrBlocks.map { block in
            OCRBlock(text: block.text, y: block.y)
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
                        let singleExercise = Exercise(
                            exerciseNumber: "1",
                            type: "other",
                            fullContent: ocrResult.fullText,
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
    func analyzeHomeworkContentForReanalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock], item: Item, context: NSManagedObjectContext) {
        // Convert OCRService.OCRBlock to OCRBlock
        let aiBlocks = ocrBlocks.map { block in
            OCRBlock(text: block.text, y: block.y)
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
    func performCloudAnalysisForReanalysis(image: UIImage, ocrBlocks: [OCRService.OCRBlock], item: Item, context: NSManagedObjectContext) {
        DispatchQueue.main.async {
            self.isCloudAnalysisInProgress = true
        }

        // Convert OCR blocks to AI service format
        let aiBlocks = ocrBlocks.map { block in
            OCRBlock(text: block.text, y: block.y)
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
            OCRBlock(text: block.text, y: block.y)
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
