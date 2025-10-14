//
//  Item+Extensions.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import Foundation
import CoreData

/// The analysis status of a homework item
public enum AnalysisStatus: String {
    case notStarted
    case inProgress
    case completed
    case failed
}

/// Extension to make Item conform to AnalyzableHomework protocol
extension Item: AnalyzableHomework {

    /// The analysis status of the homework item
    public var analysisStatus: AnalysisStatus {
        if analysisJSON == "inProgress" {
            return .inProgress
        } else if analysisJSON == "failed" {
            return .failed
        } else if analysisJSON != nil {
            return .completed
        } else {
            return .notStarted
        }
    }
    public var id: String {
        self.objectID.uriRepresentation().absoluteString
    }

    public var title: String {
        if let text = extractedText, !text.isEmpty {
            // Return first line or truncated text
            let lines = text.components(separatedBy: .newlines)
            if let firstLine = lines.first, !firstLine.isEmpty {
                return String(firstLine.prefix(50))
            }
        }
        if let date = timestamp {
            return "Homework from \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Homework"
    }

    public var date: Date? {
        timestamp
    }

    // AnalyzableHomework requires exerciseAnswers as [String: Data]?
    // Core Data has exerciseAnswersData as Data
    public var exerciseAnswers: [String: Data]? {
        get {
            guard let data = exerciseAnswersData else {
                return nil
            }
            return try? JSONDecoder().decode([String: Data].self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                exerciseAnswersData = data
            } else {
                exerciseAnswersData = nil
            }
        }
    }
}
