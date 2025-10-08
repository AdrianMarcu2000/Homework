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

            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")

            if recognizedText.isEmpty {
                completion(.failure(OCRError.noTextFound))
            } else {
                completion(.success(recognizedText))
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
