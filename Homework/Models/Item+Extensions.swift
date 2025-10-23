//
//  Item+Extensions.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import Foundation
import CoreData

/// The analysis status of a homework item
public enum AnalysisStatus: String {
    case notStarted
    case inProgress
    case completed
    case failed
}

/// The method used to analyze the homework
public enum AnalysisMethod: String {
    case none = "none"              // No analysis performed
    case ocrOnly = "ocr_only"       // Basic OCR without AI
    case appleAI = "apple_ai"       // Apple Intelligence (on-device)
    case cloudAI = "cloud_ai"       // Google Gemini (cloud)
}

/// Extension to make Item conform to AnalyzableHomework protocol
extension Item: AnalyzableHomework {

    /// Whether this homework is a PDF (has pdfFilePath)
    var isPDF: Bool {
        return pdfFilePath != nil && !pdfFilePath!.isEmpty
    }

    /// Get the full file URL for the stored PDF
    var pdfFileURL: URL? {
        guard let filePath = pdfFilePath else { return nil }
        return try? PDFStorageService.shared.getFileURL(for: filePath)
    }

    /// Load the PDF data from storage
    func loadPDFData() throws -> Data {
        guard let filePath = pdfFilePath else {
            throw PDFStorageError.invalidPath
        }
        return try PDFStorageService.shared.loadPDF(from: filePath)
    }

    /// The analysis status of the homework item
    public var analysisStatus: AnalysisStatus {
        if analysisJSON == "inProgress" {
            return .inProgress
        } else if analysisJSON == "failed" {
            return .failed
        } else if analysisJSON != nil {
            return .completed
        } else {
            return .notStarted
        }
    }

    /// The method used to analyze this homework
    public var usedAnalysisMethod: AnalysisMethod {
        guard let method = analysisMethod else {
            return .none
        }
        return AnalysisMethod(rawValue: method) ?? .none
    }
    public var id: String {
        self.objectID.uriRepresentation().absoluteString
    }

    public var title: String {
        if let text = extractedText, !text.isEmpty {
            // Return first line or truncated text
            let lines = text.components(separatedBy: .newlines)
            if let firstLine = lines.first, !firstLine.isEmpty {
                return String(firstLine.prefix(50))
            }
        }
        if let date = timestamp {
            return "Homework from \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Homework"
    }

    public var date: Date? {
        timestamp
    }

    // subject property is now provided by AnalyzableHomework protocol extension

    // AnalyzableHomework requires exerciseAnswers as [String: Data]?
    // Core Data has exerciseAnswersData as Data
    public var exerciseAnswers: [String: Data]? {
        get {
            guard let data = exerciseAnswersData else {
                return nil
            }
            return try? JSONDecoder().decode([String: Data].self, from: data)
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue) {
                exerciseAnswersData = data
            } else {
                exerciseAnswersData = nil
            }
        }
    }

    // MARK: - AnalyzableHomework Protocol Methods

    /// Save the analysis result to Core Data
    public func saveAnalysis(_ analysis: AnalysisResult) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(analysis)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            self.analysisJSON = jsonString
        }
        try self.managedObjectContext?.save()
    }

    /// Save exercise answers to Core Data
    public func saveAnswers() throws {
        // exerciseAnswers setter already handles encoding
        // Just need to save the context
        try self.managedObjectContext?.save()
    }
}
