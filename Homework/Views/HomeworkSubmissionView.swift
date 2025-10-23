//
//  `HomeworkSubmissionView.swift`
//  Homework
//
//  Created by Claude on 18.10.2025.
//

import SwiftUI
import PencilKit
import OSLog

/// View for assembling and displaying homework submission before turning in
struct HomeworkSubmissionView: View {
    @ObservedObject var assignment: ClassroomAssignment
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showSuccessAlert = false
    @State private var driveFileId: String?
    @State private var showClassroomInApp = false

    private var exercisesWithAnswers: [(exercise: Exercise, answer: Data?)] {
        guard let analysis = assignment.analysisResult else { return [] }

        return analysis.exercises.map { exercise in
            let answerKey = "\(exercise.exerciseNumber)_\(exercise.startY)"
            let answer = assignment.exerciseAnswers?[answerKey]
            return (exercise, answer)
        }
    }

    private var hasAnyAnswers: Bool {
        exercisesWithAnswers.contains { $0.answer != nil }
    }

    // Can submit if status allows modification (NEW, CREATED, or RECLAIMED_BY_STUDENT)
    private var canSubmit: Bool {
        switch assignment.status {
        case .new, .created, .reclaimedByStudent:
            return true
        case .turnedIn, .returned:
            return false
        }
    }

    private var submitButtonText: String {
        if isSubmitting {
            return "Turning In..."
        } else if assignment.status == .turnedIn {
            return "Already Turned In"
        } else if assignment.status == .returned {
            return "Returned by Teacher"
        } else {
            return "Turn In"
        }
    }

    var body: some View {
        ZStack {
            // Dark background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissView()
                }

            GeometryReader { geometry in
                // A4 Paper container - Full height with A4 aspect ratio
                VStack(spacing: 0) {
                    // Close button overlay
                    HStack {
                        Button(action: { dismissView() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        .padding()
                        Spacer()
                    }
                    .zIndex(1)
                    .offset(y: -50)

                    // Header
                    VStack(spacing: 8) {
                        Text("Review Your Homework")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Check your answers before turning in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Submission status indicator
                        HStack(spacing: 6) {
                            if assignment.isSyncingStatus {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Image(systemName: assignment.status.iconName)
                                .font(.caption)
                            Text("Status: \(assignment.status.displayName)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(assignment.status.color).opacity(0.2))
                        .foregroundColor(Color(assignment.status.color))
                        .cornerRadius(8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))

                    Divider()

                    // Exercises and answers
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(Array(exercisesWithAnswers.enumerated()), id: \.offset) { index, item in
                                ExerciseSubmissionCard(
                                    exerciseNumber: item.exercise.exerciseNumber,
                                    fullContent: item.exercise.fullContent,
                                    answerData: item.answer,
                                    subject: item.exercise.subject,
                                    imageData: assignment.imageData,
                                    startY: item.exercise.startY,
                                    endY: item.exercise.endY
                                )
                            }

                            if !hasAnyAnswers {
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.orange)
                                    Text("No Answers Found")
                                        .font(.headline)
                                    Text("You haven't answered any exercises yet.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }

                    // Error message
                    if let error = submitError {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }

                    // Turn in button
                    Button(action: turnInHomework) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: assignment.status == .turnedIn ? "checkmark.circle.fill" : "paperplane.fill")
                            }
                            Text(submitButtonText)
                        }
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            canSubmit && hasAnyAnswers
                                ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting || !hasAnyAnswers || !canSubmit)
                    .padding()
                }
                .frame(width: a4Width(for: geometry.size.height), height: geometry.size.height)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 10)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            Task {
                await assignment.syncStatusWithGoogleClassroom()
            }
        }
        .alert("Success!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismissView()
            }
        } message: {
            Text("Your homework has been turned in successfully!")
        }
    }

    // MARK: - Helpers

    /// Calculate A4 width based on available height (A4 ratio is 1:1.414)
    private func a4Width(for height: CGFloat) -> CGFloat {
        let a4Ratio: CGFloat = 1.0 / 1.414  // Width to height ratio for A4
        return (height * 0.95) * a4Ratio
    }

    /// Dismiss the view
    private func dismissView() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    // MARK: - Actions

    private func turnInHomework() {
        isSubmitting = true
        submitError = nil

        Task {
            do {
                // Generate PDF
                let pdfData = try await PDFGenerationService.shared.generateHomeworkPDF(
                    assignment: assignment,
                    exercisesWithAnswers: exercisesWithAnswers
                )

                AppLogger.google.info("PDF generated: \(pdfData.count) bytes")

                // Submit to Google Classroom
                let fileId = try await GoogleClassroomService.shared.turnInAssignment(
                    courseId: assignment.coursework.courseId,
                    courseWorkId: assignment.coursework.id,
                    pdfData: pdfData,
                    fileName: "\(assignment.title)_\(UUID().uuidString).pdf"
                )

                AppLogger.google.info("Homework submitted successfully")

                // Re-sync status from Google Classroom to get the updated TURNED_IN state
                await assignment.syncStatusWithGoogleClassroom()

                await MainActor.run {
                    isSubmitting = false
                    driveFileId = fileId
                    showSuccessAlert = true
                }
            } catch {
                AppLogger.google.error("Failed to submit homework", error: error)
                await MainActor.run {
                    isSubmitting = false
                    submitError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Supporting Views

/// Card displaying an exercise and its answer for submission review
private struct ExerciseSubmissionCard: View {
    let exerciseNumber: String
    let fullContent: String
    let answerData: Data?
    let subject: String?
    let imageData: Data?
    let startY: Double
    let endY: Double

    private var croppedExerciseImage: UIImage? {
        guard let imageData = imageData,
              let fullImage = UIImage(data: imageData) else {
            return nil
        }
        return fullImage.crop(startY: startY, endY: endY, padding: 0.03)
    }

    /// Render the full canvas image with background, not cropped to drawing bounds
    private func renderFullCanvasImage(drawing: PKDrawing, canvasSize: CGSize, isMath: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            // Draw background
            if isMath {
                UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0).setFill()
            } else {
                UIColor.white.setFill()
            }
            context.fill(CGRect(origin: .zero, size: canvasSize))

            // Draw the full canvas drawing
            let drawingRect = CGRect(origin: .zero, size: canvasSize)
            drawing.image(from: drawingRect, scale: 1.0).draw(in: drawingRect)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise header
            HStack {
                HStack(spacing: 6) {
                    Text("Exercise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text(exerciseNumber)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                Spacer()
            }

            // Exercise image (if available)
            if let croppedImage = croppedExerciseImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }

            // Exercise content
            Text(fullContent)
                .font(.body)
                .foregroundColor(.primary)

            Divider()

            // Answer section
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Answer:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if let answerData = answerData,
                   let drawing = try? PKDrawing(data: answerData) {
                    // Display full canvas drawing (not cropped to bounds)
                    let isMath = subject == "mathematics"

                    // Use a fixed canvas size for consistent display
                    let canvasSize = CGSize(width: 800, height: 400)
                    let drawingImage = renderFullCanvasImage(drawing: drawing, canvasSize: canvasSize, isMath: isMath)

                    Image(uiImage: drawingImage)
                        .resizable()
                        .aspectRatio(canvasSize.width / canvasSize.height, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    // No answer
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Not answered")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}


#Preview {
    let mockCoursework = ClassroomCoursework(
        id: "1",
        courseId: "course1",
        title: "Math Homework - Chapter 5",
        description: "Complete exercises 1-10 from Chapter 5",
        materials: nil,
        state: "PUBLISHED",
        creationTime: "2025-10-18T10:00:00Z",
        updateTime: nil,
        dueDate: nil,
        maxPoints: 100,
        workType: "ASSIGNMENT",
        alternateLink: nil
    )

    HomeworkSubmissionView(assignment: ClassroomAssignment(coursework: mockCoursework, courseName: "Mathematics"))
}
