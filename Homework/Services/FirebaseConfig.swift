//
//  FirebaseConfig.swift
//  Homework
//
//  Centralized Firebase Functions configuration
//  Single source of truth for all Firebase endpoint URLs
//

import Foundation

/// Centralized configuration for Firebase Functions endpoints
enum FirebaseConfig {
    /// Firebase project ID (must match GoogleService-Info.plist)
    private static let projectID = "homework-daef1"

    /// Firebase region for Cloud Functions
    private static let region = "us-central1"

    /// Base URL for Firebase Functions
    /// - In DEBUG: Uses local emulator
    /// - In RELEASE: Uses production Cloud Functions
    static var baseURL: String {
        #if DEBUG
        return "http://127.0.0.1:5001/\(projectID)/\(region)"
        #else
        return "https://\(region)-\(projectID).cloudfunctions.net"
        #endif
    }

    /// Timeout configurations for different types of operations
    enum Timeouts {
        /// Standard analysis operations (single image)
        static let standardRequest: TimeInterval = 120 // 2 minutes
        static let standardResource: TimeInterval = 180 // 3 minutes

        /// Agentic analysis operations (multi-agent, may take longer)
        static let agenticRequest: TimeInterval = 180 // 3 minutes
        static let agenticResource: TimeInterval = 240 // 4 minutes

        /// Quick operations (hints, verification)
        static let quickRequest: TimeInterval = 60 // 1 minute
        static let quickResource: TimeInterval = 90 // 1.5 minutes
    }

    /// Retry configurations
    enum Retry {
        static let maxRetries = 2
        static let delaySeconds: TimeInterval = 2
    }

    /// Available Firebase Function endpoints
    enum Endpoint: String {
        case analyzeHomework
        case analyzeHomeworkAgentic
        case analyzeTextOnly
        case verifyAnswer
        case generateHints
        case generateSimilarExercises

        /// Full URL for this endpoint
        var url: URL {
            URL(string: "\(FirebaseConfig.baseURL)/\(self.rawValue)")!
        }
    }
}
