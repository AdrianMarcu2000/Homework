//
//  HomeworkCaptureViewModel+Analyzer.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import CoreData
import OSLog

extension HomeworkCaptureViewModel {
    // MARK: - HomeworkAnalyzer Protocol

    var isAnalyzing: Bool {
        isProcessingOCR || isCloudAnalysisInProgress
    }

    func analyzeWithAppleAI(homework: any AnalyzableHomework) {
        guard let item = homework as? Item else {
            AppLogger.ai.error("Cannot analyze non-Item homework with this view model")
            return
        }
        reanalyzeHomework(item: item, context: initialContext, useCloud: false)
    }

    func analyzeWithCloudAI(homework: any AnalyzableHomework) {
        guard let item = homework as? Item else {
            AppLogger.ai.error("Cannot analyze non-Item homework with this view model")
            return
        }
        reanalyzeHomework(item: item, context: initialContext, useCloud: true)
    }
}
