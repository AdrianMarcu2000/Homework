//
//  `HomeworkSubmissionView.swift`
//  Homework
//
//  Created by Claude on 18.10.2025.
//

import SwiftUI
import PencilKit

/// View for assembling and displaying homework submission before turning in
struct HomeworkSubmissionView: View {
    let assignment: ClassroomAssignment
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showSuccessAlert = false
    @State private var driveFileId: String?
    @State private var submissionState: String?
    @State private var showClassroomInApp = false

    private var exercisesWithAnswers: [(exercise: AIAnalysisService.Exercise, answer: Data?)] {
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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Review Your Homework")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Check your answers before turning in")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Submission state indicator
                    if let state = submissionState {
                        HStack(spacing: 6) {
                            Image(systemName: stateIcon(for: state))
                                .font(.caption)
                            Text("Status: \(stateDisplayName(for: state))")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(stateColor(for: state).opacity(0.2))
                        .foregroundColor(stateColor(for: state))
                        .cornerRadius(8)
                    }
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
                            Text("Turning In...")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Turn In")
                        }
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(hasAnyAnswers ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !hasAnyAnswers)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSubmissionState()
            }
        }
        .alert("Success!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your homework has been turned in successfully!")
        }
    }

    // MARK: - Actions

    private func loadSubmissionState() {
        Task {
            do {
                let accessToken = try await GoogleAuthService.shared.getAccessToken()
                let url = URL(string: "https://classroom.googleapis.com/v1/courses/\(assignment.coursework.courseId)/courseWork/\(assignment.coursework.id)/studentSubmissions")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                let (data, _) = try await URLSession.shared.data(for: request)

                struct SubmissionsResponse: Codable {
                    let studentSubmissions: [Submission]?
                }

                struct Submission: Codable {
                    let state: String
                }

                let response = try JSONDecoder().decode(SubmissionsResponse.self, from: data)
                if let state = response.studentSubmissions?.first?.state {
                    await MainActor.run {
                        submissionState = state
                    }
                }
            } catch {
                print("❌ Failed to load submission state: \(error)")
            }
        }
    }

    private func stateDisplayName(for state: String) -> String {
        switch state {
        case "NEW": return "Not Started"
        case "CREATED": return "In Progress"
        case "TURNED_IN": return "Turned In"
        case "RETURNED": return "Returned"
        case "RECLAIMED_BY_STUDENT": return "Reclaimed"
        default: return state
        }
    }

    private func stateColor(for state: String) -> Color {
        switch state {
        case "NEW", "CREATED", "RECLAIMED_BY_STUDENT": return .orange
        case "TURNED_IN": return .green
        case "RETURNED": return .blue
        default: return .gray
        }
    }

    private func stateIcon(for state: String) -> String {
        switch state {
        case "NEW", "CREATED": return "circle.fill"
        case "TURNED_IN": return "checkmark.circle.fill"
        case "RETURNED": return "arrow.uturn.backward.circle.fill"
        case "RECLAIMED_BY_STUDENT": return "arrow.counterclockwise.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

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

                print("✅ PDF generated: \(pdfData.count) bytes")

                // Submit to Google Classroom
                let fileId = try await GoogleClassroomService.shared.turnInAssignment(
                    courseId: assignment.coursework.courseId,
                    courseWorkId: assignment.coursework.id,
                    pdfData: pdfData,
                    fileName: "\(assignment.title)_\(UUID().uuidString).pdf"
                )

                print("✅ Homework submitted successfully")

                await MainActor.run {
                    isSubmitting = false
                    driveFileId = fileId
                    submissionState = "TURNED_IN"
                    showSuccessAlert = true
                }
            } catch {
                print("❌ Failed to submit homework: \(error)")
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
                    // Display canvas drawing
                    let isMath = subject == "mathematics"
                    Image(uiImage: drawing.image(from: drawing.bounds, scale: 2.0))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 150)
                        .background(isMath ? Color(red: 1.0, green: 0.98, blue: 0.94) : Color.white)
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
