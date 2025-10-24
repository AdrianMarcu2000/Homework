
//
//  ClassroomExerciseCardView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Type alias for ClassroomAssignment exercise card using the generic implementation
typealias ClassroomExerciseCardView = ExerciseCardView<ClassroomAssignment>

/// Extension to provide a convenient initializer for ClassroomExerciseCardView
extension ExerciseCardView where Homework == ClassroomAssignment {
    init(exercise: Exercise, assignment: ClassroomAssignment) {
        self.init(
            exercise: exercise,
            homework: assignment,
            onAnswerChange: {
                assignment.saveToCache()
            }
        )
    }
}
