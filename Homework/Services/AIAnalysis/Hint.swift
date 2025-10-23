
//
//  Hint.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Progressive hint for an exercise
struct Hint: Codable, Identifiable {
    var id: UUID { UUID() }
    let level: Int // 1, 2, 3 or 4
    let title: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case level, title, content
    }
}
