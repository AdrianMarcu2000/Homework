//
//  OCRService.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import UIKit
import Vision

/// A service class that provides OCR (Optical Character Recognition) functionality
/// using Apple's Vision framework to extract text from images.
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
            completion(.failure(OCRError.invalidImage))
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
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
                    let boundingBox = observation.boundingBox
                    let yCoordinate = boundingBox.origin.y

                    blocks.append(OCRBlock(text: text, y: yCoordinate))
                }
            }

            let fullText = textStrings.joined(separator: "\n")

            if fullText.isEmpty {
                completion(.failure(OCRError.noTextFound))
            } else {
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
                completion(.failure(error))
            }
        }
    }

    /// Custom errors that can occur during OCR processing
    enum OCRError: LocalizedError {
        /// The provided image could not be converted to CGImage
        case invalidImage
        /// No text was detected in the image
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "The provided image is invalid"
            case .noTextFound:
                return "No text was found in the image"
            }
        }
    }
}
