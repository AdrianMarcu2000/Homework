
//
//  AnalysisRequest.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Request structure for cloud analysis (single image - legacy)
struct AnalysisRequest: Sendable {
    let imageBase64: String
    let imageMimeType: String
    let ocrJsonText: String
}

// Explicitly implement Encodable outside of MainActor context
extension AnalysisRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case imageBase64, imageMimeType, ocrJsonText
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageBase64, forKey: .imageBase64)
        try container.encode(imageMimeType, forKey: .imageMimeType)
        try container.encode(ocrJsonText, forKey: .ocrJsonText)
    }
}
