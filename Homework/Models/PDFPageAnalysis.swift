//
//  PDFPageAnalysis.swift
//  Homework
//
//  Data structure for storing per-page analysis in PDF homework
//

import Foundation

/// Represents analysis data for a single page in a PDF homework
struct PDFPageAnalysis: Codable {
    /// The page number (1-indexed)
    let pageNumber: Int

    /// The AI analysis result for this page
    let analysisResult: AIAnalysisService.AnalysisResult

    /// Exercise answers for this specific page (key format: "exerciseNumber_startY_type")
    var exerciseAnswers: [String: Data]

    /// The analysis method used for this page
    let analysisMethod: String

    /// When this page was analyzed
    let analyzedAt: Date

    init(pageNumber: Int, analysisResult: AIAnalysisService.AnalysisResult, analysisMethod: String) {
        self.pageNumber = pageNumber
        self.analysisResult = analysisResult
        self.exerciseAnswers = [:]
        self.analysisMethod = analysisMethod
        self.analyzedAt = Date()
    }
}

/// Container for all page analyses in a PDF homework
struct PDFHomeworkAnalysis: Codable {
    /// Map of page number to analysis data
    var pageAnalyses: [Int: PDFPageAnalysis]

    init() {
        self.pageAnalyses = [:]
    }

    /// Get analysis for a specific page
    func analysis(for pageNumber: Int) -> PDFPageAnalysis? {
        return pageAnalyses[pageNumber]
    }

    /// Set or update analysis for a specific page
    mutating func setAnalysis(_ analysis: PDFPageAnalysis, for pageNumber: Int) {
        pageAnalyses[pageNumber] = analysis
    }

    /// Check if a page has been analyzed
    func hasAnalysis(for pageNumber: Int) -> Bool {
        return pageAnalyses[pageNumber] != nil
    }

    /// Get all analyzed page numbers sorted
    func analyzedPages() -> [Int] {
        return pageAnalyses.keys.sorted()
    }
}
