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
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AIAnalysisService.AnalysisResult.self, from: jsonData)
        } catch {
            print("Error decoding analysis result: \(error)")
            return nil
        }
    }
}
