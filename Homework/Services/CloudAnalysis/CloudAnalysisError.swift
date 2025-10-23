
//
//  CloudAnalysisError.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Errors that can occur during cloud analysis
enum CloudAnalysisError: LocalizedError {
    case imageConversionFailed
    case encodingFailed(Error)
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case noData
    case decodingFailed(Error)
    case appCheckFailed(Error)
    case noAppCheckToken

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG format"
        case .encodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                return "Request timed out. The server took too long to respond. Please try again."
            }
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            if code >= 500 {
                return "Server is temporarily unavailable (\(code)). Please try again in a moment."
            }
            return "Server error (\(code)): \(message)"
        case .noData:
            return "No data received from server"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .appCheckFailed(let error):
            return "App Check verification failed: \(error.localizedDescription)"
        case .noAppCheckToken:
            return "Failed to obtain App Check token"
        }
    }
}
