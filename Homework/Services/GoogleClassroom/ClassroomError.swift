
//
//  ClassroomError.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

// MARK: - Errors

enum ClassroomError: LocalizedError {
    case apiError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Google Classroom API error: \(message)"
        case .notAuthenticated:
            return "Not authenticated with Google"
        }
    }
}
