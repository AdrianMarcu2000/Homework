
//
//  AIAnalysisError.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Errors that can occur during AI analysis
enum AIAnalysisError: LocalizedError {
    case unsupportedVersion
    case parsingFailed(Error)
    case analysisUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "Apple Intelligence requires iOS 18.1 or later"
        case .parsingFailed(let error):
            return "Failed to parse analysis result: \(error.localizedDescription)"
        case .analysisUnavailable:
            return "Apple Intelligence is not available on this device"
        }
    }
}
