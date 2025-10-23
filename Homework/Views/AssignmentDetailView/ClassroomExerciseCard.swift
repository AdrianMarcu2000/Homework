
//
//  ClassroomExerciseCard.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

struct ClassroomExerciseCard: View {
    let exercise: Exercise
    @ObservedObject var assignment: ClassroomAssignment

    var body: some View {
        ExerciseCardContent(
            exercise: exercise,
            imageData: assignment.imageData,
            exerciseAnswers: Binding(
                get: { assignment.exerciseAnswers },
                set: { assignment.exerciseAnswers = $0; assignment.saveToCache() }
            )
        )
    }
}
