
//
//  Exercise.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Represents an exercise segment
public struct Exercise: Codable, Hashable, Sendable {
    public let exerciseNumber: String
    public let type: String
    public let fullContent: String
    public let startY: Double
    public let endY: Double
    public let subject: String? // mathematics, language, science, history, etc.
    public let inputType: String? // text, canvas, both

    // Custom decoding to handle null exerciseNumber and optional fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // If exerciseNumber is null, use "Unknown"
        if let number = try container.decodeIfPresent(String.self, forKey: .exerciseNumber) {
            self.exerciseNumber = number
        } else {
            self.exerciseNumber = "Unknown"
        }

        self.type = try container.decode(String.self, forKey: .type)
        self.fullContent = try container.decode(String.self, forKey: .fullContent)
        self.startY = try container.decode(Double.self, forKey: .startY)
        self.endY = try container.decode(Double.self, forKey: .endY)
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject)
        self.inputType = try container.decodeIfPresent(String.self, forKey: .inputType) ?? "canvas" // default to canvas
    }

    // Regular init for non-decoded creation
    nonisolated public init(exerciseNumber: String, type: String, fullContent: String, startY: Double, endY: Double, subject: String? = nil, inputType: String? = "canvas") {
        self.exerciseNumber = exerciseNumber
        self.type = type
        self.fullContent = fullContent
        self.startY = startY
        self.endY = endY
        self.subject = subject
        self.inputType = inputType
    }

    enum CodingKeys: String, CodingKey {
        case exerciseNumber, type, fullContent, startY, endY, subject, inputType
    }
}
