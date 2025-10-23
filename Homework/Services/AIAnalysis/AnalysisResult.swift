
//
//  AnalysisResult.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Analysis result containing exercises
public struct AnalysisResult: Codable {
    public let exercises: [Exercise]

    public init(exercises: [Exercise]) {
        self.exercises = exercises
    }
}
