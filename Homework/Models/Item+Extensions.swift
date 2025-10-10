//
//  Item+Extensions.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import Foundation
import CoreData

/// Extension to provide typed access to Item properties and helper methods
extension Item {
    /// Computed property to safely access analysisJSON
    var analysis: String? {
        get {
            value(forKey: "analysisJSON") as? String
        }
        set {
            setValue(newValue, forKey: "analysisJSON")
        }
    }

    /// Decodes and returns the AI analysis result from stored JSON
    var analysisResult: AIAnalysisService.AnalysisResult? {
        guard let jsonString = analysis,
              let jsonData = jsonString.data(using: .utf8) else {
            print("DEBUG DECODE: No analysis JSON found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(AIAnalysisService.AnalysisResult.self, from: jsonData)
            print("DEBUG DECODE: Successfully decoded - Exercises: \(result.exercises.count)")
            print("DEBUG DECODE: Exercise order from JSON:")
            for (idx, ex) in result.exercises.enumerated() {
                print("  Position \(idx): Exercise #\(ex.exerciseNumber), Y: \(ex.startY)-\(ex.endY)")
            }
            return result
        } catch {
            print("DEBUG DECODE: Error decoding analysis result: \(error)")
            return nil
        }
    }

    /// Computed property to store exercise answers (drawings)
    var exerciseAnswers: [String: Data]? {
        get {
            guard let data = value(forKey: "exerciseAnswersData") as? Data else {
                return nil
            }
            return try? JSONDecoder().decode([String: Data].self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                setValue(data, forKey: "exerciseAnswersData")
            } else {
                setValue(nil, forKey: "exerciseAnswersData")
            }
        }
    }
}
