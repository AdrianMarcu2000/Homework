//
//  AppLogger.swift
//  Homework
//
//  Centralized logging configuration using Swift's OSLog framework
//

import Foundation
import OSLog

/// Centralized logging subsystem for the Homework app
///
/// Usage:
/// - For informational messages (user actions, state changes): `AppLogger.ui.info("User tapped button")`
/// - For debugging (detailed flow info): `AppLogger.ui.debug("Processing started")`
/// - For errors: `AppLogger.ui.error("Failed to load", error: error)`
/// - For critical issues: `AppLogger.ui.critical("Database corruption detected")`
///
/// All logs are automatically prefixed with "BlueFern.Homework" and include icons for visual clarity.
struct AppLogger {

    /// Bundle identifier used as subsystem
    private static let subsystem = Bundle.main.bundleIdentifier ?? "BlueFern.Homework"

    // MARK: - Logger Categories

    /// Logger for UI and user interactions
    /// Use for: button taps, navigation, user input, sheet presentations
    static let ui = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "UI"))

    /// Logger for OCR operations
    /// Use for: Vision framework operations, text recognition, OCR processing
    static let ocr = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "OCR"))

    /// Logger for AI analysis operations
    /// Use for: Apple Intelligence interactions, prompt generation, response parsing
    static let ai = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "AI"))

    /// Logger for cloud services
    /// Use for: Firebase operations, cloud functions, network requests
    static let cloud = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Cloud"))

    /// Logger for Google services
    /// Use for: Google Auth, Classroom API, Drive API
    static let google = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Google"))

    /// Logger for Core Data operations
    /// Use for: persistence, data model operations, CloudKit sync
    static let persistence = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Persistence"))

    /// Logger for authentication and security
    /// Use for: biometric auth, Face ID, Touch ID, App Check
    static let auth = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Auth"))

    /// Logger for subscription and payments
    /// Use for: StoreKit operations, subscription status
    static let subscription = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Subscription"))

    /// Logger for image processing
    /// Use for: image segmentation, cropping, compression
    static let image = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Image"))

    /// Logger for general app lifecycle
    /// Use for: app launch, initialization, configuration
    static let lifecycle = LoggerWrapper(logger: Logger(subsystem: subsystem, category: "Lifecycle"))
}

// MARK: - Logger Wrapper

/// Wrapper around Logger to add custom formatting
struct LoggerWrapper {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    /// Log an info message
    func info(_ message: String) {
        logger.log(level: .info, "ℹ️ BlueFern.Homework | \(message)")
    }

    /// Log a debug message
    func debug(_ message: String) {
        logger.log(level: .debug, "🔍 BlueFern.Homework | \(message)")
    }

    /// Log an error message
    func error(_ message: String) {
        logger.log(level: .error, "❌ BlueFern.Homework | \(message)")
    }

    /// Log a warning message
    func warning(_ message: String) {
        logger.log(level: .default, "⚠️ BlueFern.Homework | \(message)")
    }

    /// Log an error with detailed information
    func error(_ message: String, error: Error) {
        logger.log(level: .error, "❌ BlueFern.Homework | \(message): \(error.localizedDescription)")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log an error with detailed information
    /// - Parameters:
    ///   - message: Error description
    ///   - error: The error object
    func error(_ message: String, error: Error) {
        self.error("❌ BlueFern.Homework | \(message): \(error.localizedDescription)")
    }

    /// Log a network request
    /// - Parameters:
    ///   - method: HTTP method
    ///   - url: Request URL
    func logRequest(_ method: String, url: URL) {
        self.log(level: .info, "🌐 BlueFern.Homework | [\(method)] \(url.absoluteString)")
    }

    /// Log a network response
    /// - Parameters:
    ///   - statusCode: HTTP status code
    ///   - url: Response URL
    func logResponse(statusCode: Int, url: URL) {
        if statusCode >= 200 && statusCode < 300 {
            self.log(level: .info, "✅ BlueFern.Homework | [\(statusCode)] \(url.absoluteString)")
        } else if statusCode >= 400 {
            self.log(level: .error, "❌ BlueFern.Homework | [\(statusCode)] \(url.absoluteString)")
        } else {
            self.log(level: .debug, "🔍 BlueFern.Homework | [\(statusCode)] \(url.absoluteString)")
        }
    }
}
