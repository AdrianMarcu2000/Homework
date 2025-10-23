
//
//  HomeworkCaptureViewModel+OCR.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

extension HomeworkCaptureViewModel {
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
                let aiBlocks = ocrResult.blocks.map { OCRBlock(text: $0.text, y: $0.y) }

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
}
