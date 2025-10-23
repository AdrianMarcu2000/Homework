
//
//  SegmentAnalysisResult.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

/// Result from analyzing a single segment
struct SegmentAnalysisResult: Codable {
    let type: String // "exercise" or "skip"
    let exercise: Exercise?
}
