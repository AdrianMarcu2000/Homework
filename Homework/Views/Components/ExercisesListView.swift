//
//  ExercisesListView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Shared exercises list view
struct ExercisesListView<Homework: AnalyzableHomework>: View {
    var analysis: AnalysisResult
    var homework: Homework
    var onAnswerChange: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(analysis.exercises, id: \.self) { exercise in
                    ExerciseCardView(
                        exercise: exercise,
                        homework: homework,
                        onAnswerChange: onAnswerChange
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}
