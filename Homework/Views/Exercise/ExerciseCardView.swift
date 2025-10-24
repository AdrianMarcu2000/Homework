//
//  ExerciseCardView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// A generic exercise card that works with any AnalyzableHomework type
struct ExerciseCardView<Homework: AnalyzableHomework>: View {
    let exercise: Exercise
    var homework: Homework
    var onAnswerChange: (() -> Void)?

    var body: some View {
        ExerciseCardContentView(
            exercise: exercise,
            imageData: homework.imageData,
            exerciseAnswers: Binding(
                get: { homework.exerciseAnswers },
                set: { newValue in
                    homework.exerciseAnswers = newValue
                    onAnswerChange?()
                }
            )
        )
    }
}
