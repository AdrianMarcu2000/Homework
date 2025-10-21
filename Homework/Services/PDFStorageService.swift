//
//  PDFStorageService.swift
//  Homework
//
//  Service for managing PDF file storage in the app's Application Support directory
//

import Foundation
import OSLog

class PDFStorageService {
    static let shared = PDFStorageService()

    private init() {}

    /// The directory where PDF files are stored (Application Support/PDFs)
    private var pdfStorageDirectory: URL {
        get throws {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let pdfDirectory = appSupportURL.appendingPathComponent("PDFs", isDirectory: true)

            // Create directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: pdfDirectory.path) {
                try FileManager.default.createDirectory(
                    at: pdfDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                AppLogger.image.info("Created PDF storage directory at: \(pdfDirectory.path)")
            }

            return pdfDirectory
        }
    }

    /// Save PDF data to storage and return the relative file path
    /// - Parameter pdfData: The PDF file data
    /// - Returns: Relative file path (e.g., "PDFs/homework_UUID.pdf")
    func savePDF(data: Data) async throws -> String {
        let directory = try pdfStorageDirectory

        // Generate unique filename
        let filename = "homework_\(UUID().uuidString).pdf"
        let fileURL = directory.appendingPathComponent(filename)

        // Write PDF to file
        try data.write(to: fileURL)

        AppLogger.image.info("Saved PDF to: \(fileURL.path) (\(data.count) bytes)")

        // Return relative path (just the filename since it's in our PDFs directory)
        return "PDFs/\(filename)"
    }

    /// Get the full URL for a stored PDF
    /// - Parameter relativePath: The relative path (e.g., "PDFs/homework_UUID.pdf")
    /// - Returns: Full file URL
    func getFileURL(for relativePath: String) throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return appSupportURL.appendingPathComponent(relativePath)
    }

    /// Load PDF data from storage
    /// - Parameter relativePath: The relative path (e.g., "PDFs/homework_UUID.pdf")
    /// - Returns: PDF data
    func loadPDF(from relativePath: String) throws -> Data {
        let fileURL = try getFileURL(for: relativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            AppLogger.image.error("PDF file not found at: \(fileURL.path)")
            throw PDFStorageError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        AppLogger.image.info("Loaded PDF from: \(fileURL.path) (\(data.count) bytes)")

        return data
    }

    /// Delete a PDF from storage
    /// - Parameter relativePath: The relative path (e.g., "PDFs/homework_UUID.pdf")
    func deletePDF(at relativePath: String) throws {
        let fileURL = try getFileURL(for: relativePath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            AppLogger.image.info("Deleted PDF at: \(fileURL.path)")
        }
    }

    /// Check if a PDF exists in storage
    /// - Parameter relativePath: The relative path
    /// - Returns: Whether the file exists
    func pdfExists(at relativePath: String) -> Bool {
        guard let fileURL = try? getFileURL(for: relativePath) else {
            return false
        }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get the size of a stored PDF in bytes
    /// - Parameter relativePath: The relative path
    /// - Returns: File size in bytes
    func pdfSize(at relativePath: String) throws -> Int64 {
        let fileURL = try getFileURL(for: relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes[.size] as? Int64 ?? 0
    }
}

/// Errors that can occur during PDF storage operations
enum PDFStorageError: Error {
    case fileNotFound
    case invalidPath
    case saveFailed
    case deleteFailed

    var localizedDescription: String {
        switch self {
        case .fileNotFound:
            return "PDF file not found in storage"
        case .invalidPath:
            return "Invalid PDF file path"
        case .saveFailed:
            return "Failed to save PDF to storage"
        case .deleteFailed:
            return "Failed to delete PDF from storage"
        }
    }
}
