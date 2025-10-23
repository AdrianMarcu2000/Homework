
//
//  CloudAnalysisResult.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Cloud response structure matching Firebase function output
struct CloudAnalysisResult: Sendable {
    let summary: String
    let sections: [Section]

    struct Section: Sendable {
        let type: String // "EXERCISE" or "SKIP"
        let title: String
        let content: String
        let subject: String?
        let inputType: String?
        let yStart: Int
        let yEnd: Int
    }
}

// Explicitly implement Codable outside of MainActor context
extension CloudAnalysisResult: Codable {
    enum CodingKeys: String, CodingKey {
        case summary, sections
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.sections = try container.decode([Section].self, forKey: .sections)
    }
}

extension CloudAnalysisResult.Section: Codable {
    enum CodingKeys: String, CodingKey {
        case type, title, content, subject, inputType, yStart, yEnd
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject)
        self.inputType = try container.decodeIfPresent(String.self, forKey: .inputType)
        self.yStart = try container.decode(Int.self, forKey: .yStart)
        self.yEnd = try container.decode(Int.self, forKey: .yEnd)
    }
}
