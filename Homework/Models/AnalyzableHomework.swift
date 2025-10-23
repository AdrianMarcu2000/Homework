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

    /// JSON string of the analysis result (settable for persistence)
    var analysisJSON: String? { get set }

    /// Dictionary of exercise answers (exercise key -> answer data)
    var exerciseAnswers: [String: Data]? { get set }

    /// Save the analysis result to persistent storage
    func saveAnalysis(_ analysis: AnalysisResult) throws

    /// Save exercise answers to persistent storage
    func saveAnswers() throws
}

/// Extension to provide default implementations for common operations
extension AnalyzableHomework {
    /// Parsed analysis result from JSON
    var analysisResult: AnalysisResult? {
        guard let json = analysisJSON,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    /// Primary subject of the homework based on exercises
    var subject: String {
        guard let analysis = analysisResult else {
            return "Other"
        }

        // Count exercises by subject
        var subjectCounts: [String: Int] = [:]
        for exercise in analysis.exercises {
            let subject = exercise.subject?.capitalized ?? "Other"
            subjectCounts[subject, default: 0] += 1
        }

        // Return the most common subject
        if let mostCommon = subjectCounts.max(by: { $0.value < $1.value }) {
            return mostCommon.key
        }

        return "Other"
    }

    /// Get answer data for a specific exercise and answer type
    func answer(for exercise: Exercise, type: String) -> Data? {
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_\(type)"
        return exerciseAnswers?[key]
    }

    /// Save answer data for a specific exercise and answer type
    func saveAnswer(for exercise: Exercise, type: String, data: Data) {
        let key = "\(exercise.exerciseNumber)_\(exercise.startY)_\(type)"
        if exerciseAnswers == nil {
            exerciseAnswers = [:]
        }
        exerciseAnswers?[key] = data
    }
}
