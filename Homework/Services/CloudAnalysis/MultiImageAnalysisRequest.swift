
//
//  MultiImageAnalysisRequest.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Request structure for multi-image analysis
struct MultiImageAnalysisRequest: Sendable {
    let images: [ImageData]
    let ocrJsonText: String

    struct ImageData: Sendable {
        let imageBase64: String
        let imageMimeType: String
        let pageNumber: Int
    }
}

// Explicitly implement Encodable outside of MainActor context
extension MultiImageAnalysisRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case images, ocrJsonText
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(images, forKey: .images)
        try container.encode(ocrJsonText, forKey: .ocrJsonText)
    }
}

extension MultiImageAnalysisRequest.ImageData: Encodable {
    enum CodingKeys: String, CodingKey {
        case imageBase64, imageMimeType, pageNumber
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageBase64, forKey: .imageBase64)
        try container.encode(imageMimeType, forKey: .imageMimeType)
        try container.encode(pageNumber, forKey: .pageNumber)
    }
}
