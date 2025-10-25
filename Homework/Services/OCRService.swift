//
//  OCRService.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import UIKit
import Vision
import PDFKit
import OSLog

/// A service class that provides OCR (Optical Character Recognition) functionality
/// using Apple's Vision framework to extract text from images and PDFs.
///
/// This service is implemented as a singleton to provide a centralized interface
/// for text recognition throughout the app.
class OCRService {
    /// Shared singleton instance
    static let shared = OCRService()

    private init() {}

    /// Represents an OCR text block with position information
    struct OCRBlock {
        let text: String
        let y: Double // Normalized Y coordinate (0.0 to 1.0)
    }

    /// Result containing both concatenated text and positioned blocks
    struct OCRResult {
        let fullText: String
        let blocks: [OCRBlock]
    }

    // MARK: - Image OCR (Completion Handler API)

    /// Recognizes and extracts text from a given image using Vision framework.
    ///
    /// This method performs OCR asynchronously on a background queue with accurate
    /// recognition level and language correction enabled.
    ///
    /// - Parameters:
    ///   - image: The UIImage to perform text recognition on
    ///   - completion: A completion handler called on the main queue with the result
    ///     - Returns: A Result containing either the recognized text as a String or an Error
    ///
    /// - Note: The recognized text contains line breaks separating different text observations
    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        recognizeTextWithBlocks(from: image) { result in
            switch result {
            case .success(let ocrResult):
                completion(.success(ocrResult.fullText))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Recognizes and extracts text with position information from an image.
    ///
    /// This method performs OCR and returns both the full text and individual text blocks
    /// with their Y coordinates for use in AI analysis.
    ///
    /// - Parameters:
    ///   - image: The UIImage to perform text recognition on
    ///   - completion: A completion handler with OCRResult containing text and blocks
    func recognizeTextWithBlocks(from image: UIImage, completion: @escaping (Result<OCRResult, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            AppLogger.ocr.error("Invalid image: could not extract CGImage")
            completion(.failure(OCRError.invalidImage))
            return
        }

        AppLogger.ocr.debug("Starting OCR text recognition with blocks")
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                AppLogger.ocr.error("OCR recognition failed", error: error)
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                AppLogger.ocr.error("No text observations found in OCR results")
                completion(.failure(OCRError.noTextFound))
                return
            }

            // Extract text and position blocks
            var blocks: [OCRBlock] = []
            var textStrings: [String] = []

            for observation in observations {
                if let text = observation.topCandidates(1).first?.string {
                    textStrings.append(text)

                    // Get the Y coordinate (normalized 0.0 to 1.0, where 0 is top)
                    // Vision uses bottom-left origin, so flip Y: (1.0 - y)
                    let boundingBox = observation.boundingBox
                    let yCoordinate = 1.0 - boundingBox.origin.y

                    blocks.append(OCRBlock(text: text, y: yCoordinate))
                }
            }

            let fullText = textStrings.joined(separator: "\n")

            if fullText.isEmpty {
                AppLogger.ocr.error("OCR completed but no text was extracted")
                completion(.failure(OCRError.noTextFound))
            } else {
                AppLogger.ocr.info("OCR completed successfully: \(blocks.count) blocks, \(fullText.count) characters")
                let result = OCRResult(fullText: fullText, blocks: blocks)
                completion(.success(result))
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                AppLogger.ocr.error("Failed to perform OCR request", error: error)
                completion(.failure(error))
            }
        }
    }

    // MARK: - Image OCR (Async/Await API)

    /// Recognizes and extracts text from a given image using async/await.
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    /// - Returns: A String containing the recognized text
    /// - Throws: OCRError if recognition fails
    func recognizeText(from image: UIImage) async throws -> String {
        let result = try await recognizeTextWithBlocks(from: image)
        return result.fullText
    }

    /// Recognizes and extracts text with position information from an image using async/await.
    ///
    /// - Parameter image: The UIImage to perform text recognition on
    /// - Returns: OCRResult containing both full text and positioned blocks
    /// - Throws: OCRError if recognition fails
    func recognizeTextWithBlocks(from image: UIImage) async throws -> OCRResult {
        return try await withCheckedThrowingContinuation { continuation in
            recognizeTextWithBlocks(from: image) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: - PDF OCR

    /// Extracts text from an array of PDF pages using either direct text extraction or OCR
    ///
    /// This method first attempts direct text extraction (for document-based PDFs),
    /// then falls back to OCR on page images (for scanned/image-based PDFs).
    ///
    /// - Parameter pages: Array of PDFPage objects to extract text from
    /// - Returns: Array of strings containing the extracted text for each page
    /// - Throws: OCRError if text extraction fails
    func extractText(from pages: [PDFPage]) async throws -> [String] {
        var extractedTexts: [String] = []

        for page in pages {
            let text = try await extractText(from: page)
            extractedTexts.append(text)
        }

        return extractedTexts
    }

    /// Extracts text from a single PDF page
    ///
    /// - Parameter page: The PDFPage to extract text from
    /// - Returns: String containing the extracted text
    /// - Throws: OCRError if text extraction fails
    func extractText(from page: PDFPage) async throws -> String {
        // First try direct text extraction (for document-based PDFs)
        if let directText = page.string, !directText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.ocr.debug("Extracted text directly from PDF page (\(directText.count) characters)")
            return directText
        }

        // If no direct text available, use OCR on the page image (for image-based PDFs)
        AppLogger.ocr.info("PDF page has no direct text, using OCR on page image")
        let pageRect = page.bounds(for: .mediaBox)
        let pageImage = page.thumbnail(of: pageRect.size, for: .mediaBox)

        return try await recognizeText(from: pageImage)
    }

    /// Extracts text with position blocks from a single PDF page
    ///
    /// - Parameter page: The PDFPage to extract text from
    /// - Returns: OCRResult containing text and position blocks
    /// - Throws: OCRError if text extraction fails
    func extractTextWithBlocks(from page: PDFPage) async throws -> OCRResult {
        // For PDFs, we need to use OCR to get position information
        // Direct text extraction doesn't provide bounding boxes
        let pageRect = page.bounds(for: .mediaBox)
        let pageImage = page.thumbnail(of: pageRect.size, for: .mediaBox)

        return try await recognizeTextWithBlocks(from: pageImage)
    }

    /// Extracts text with position blocks from an array of PDF pages
    ///
    /// - Parameter pages: Array of PDFPage objects to extract text from
    /// - Returns: Array of OCRResult containing text and blocks for each page
    /// - Throws: OCRError if text extraction fails
    func extractTextWithBlocks(from pages: [PDFPage]) async throws -> [OCRResult] {
        var results: [OCRResult] = []

        for page in pages {
            let result = try await extractTextWithBlocks(from: page)
            results.append(result)
        }

        return results
    }

    // MARK: - Error Types

    /// Custom errors that can occur during OCR processing
    enum OCRError: LocalizedError {
        /// The provided image could not be converted to CGImage
        case invalidImage
        /// No text was detected in the image
        case noTextFound
        /// PDF processing failed
        case pdfProcessingFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "The provided image is invalid"
            case .noTextFound:
                return "No text was found in the image"
            case .pdfProcessingFailed(let message):
                return "PDF processing failed: \(message)"
            }
        }
    }
}
