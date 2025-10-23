
//
//  SimilarExercise.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Generated similar exercise
struct SimilarExercise: Codable, Identifiable {
    var id: UUID { UUID() }
    let exerciseNumber: String
    let type: String
    let content: String
    let difficulty: String // same, easier, harder

    enum CodingKeys: String, CodingKey {
        case exerciseNumber, type, content, difficulty
    }
}
