//
//  AnalyzableHomework.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation
import UIKit

/// Protocol that defines a homework item that can be analyzed for exercises
/// Note: Some properties (imageData, extractedText, analysisJSON) are provided by conforming types
protocol AnalyzableHomework: AnyObject {
    /// Unique identifier
    var id: String { get }

    /// Display title
    var title: String { get }

    /// Timestamp or date
    var date: Date? { get }

    /// The image data of the homework (read-only from protocol perspective)
    var imageData: Data? { get }

    /// Extracted text from OCR (read-only from protocol perspective)
    var extractedText: String? { get }

    /// JSON string of the analysis result (read-only from protocol perspective)
    var analysisJSON: String? { get }

    /// Dictionary of exercise answers (exercise key -> answer data)
    var exerciseAnswers: [String: Data]? { get set }
}

/// Extension to provide default implementation for analysis result parsing
extension AnalyzableHomework {
    var analysisResult: AnalysisResult? {
        guard let json = analysisJSON,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(AnalysisResult.self, from: data)
    }
}
