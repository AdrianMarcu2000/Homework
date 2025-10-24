//
//  AnalysisProgressView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Shared analysis progress view that works with any analyzer
struct AnalysisProgressView: View {
    var progress: (current: Int, total: Int)?
    var isCloudAnalysis: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = progress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text(isCloudAnalysis ? "Analyzing with cloud AI..." : "Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }
}
