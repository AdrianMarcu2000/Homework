//
//  CourseDetailView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI

/// View showing assignments (coursework) for a specific Google Classroom course
struct CourseDetailView: View {
    let course: ClassroomCourse
    @State private var coursework: [ClassroomCoursework] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAssignment: ClassroomAssignment?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading assignments...")
            } else if coursework.isEmpty {
                emptyStateView
            } else {
                assignmentsList
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(course.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let section = course.section, !section.isEmpty {
                        Text(section)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: loadCoursework) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .onAppear {
            loadCoursework()
        }
    }

    // MARK: - Assignments List

    private var assignmentsList: some View {
        NavigationStack {
            List {
                ForEach(coursework.sorted(by: { (a, b) -> Bool in
                    // Sort by due date (most urgent first)
                    guard let dateA = a.dueDate?.date, let dateB = b.dueDate?.date else {
                        return false
                    }
                    return dateA < dateB
                })) { courseworkItem in
                    NavigationLink {
                        AssignmentDetailView(
                            assignment: ClassroomAssignment(
                                coursework: courseworkItem,
                                courseName: course.name
                            )
                        )
                    } label: {
                        AssignmentRow(assignment: courseworkItem)
                    }
                }
            }
            .refreshable {
                loadCoursework()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Assignments")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("You're all caught up for this course!")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: loadCoursework) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadCoursework() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                coursework = try await GoogleClassroomService.shared.fetchCoursework(for: course.id)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                print("❌ Failed to load coursework: \(error)")
            }
        }
    }
}

// MARK: - Assignment Row

struct AssignmentRow: View {
    let assignment: ClassroomCoursework

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(assignment.title)
                    .font(.headline)

                Spacer()

                if let dueDate = assignment.dueDate?.date {
                    DueDateBadge(dueDate: dueDate)
                }
            }

            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Materials section
            if let materials = assignment.materials, !materials.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(materials.count) attachment\(materials.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Max points if available
            if let maxPoints = assignment.maxPoints {
                Text("Worth \(Int(maxPoints)) points")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Due Date Badge

struct DueDateBadge: View {
    let dueDate: Date

    private var isOverdue: Bool {
        dueDate < Date()
    }

    private var isDueSoon: Bool {
        let timeInterval = dueDate.timeIntervalSinceNow
        return timeInterval > 0 && timeInterval < 86400 * 3 // 3 days
    }

    private var badgeColor: Color {
        if isOverdue {
            return .red
        } else if isDueSoon {
            return .orange
        } else {
            return .blue
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(isOverdue ? "Overdue" : "Due")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(badgeColor)

            Text(dueDate, formatter: dueDateFormatter)
                .font(.caption2)
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Formatters

private let dueDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()

// MARK: - Preview

#Preview {
    NavigationView {
        CourseDetailView(course: ClassroomCourse(
            id: "1",
            name: "Mathematics",
            section: "Period 3",
            descriptionHeading: "Advanced Algebra",
            room: "Room 101",
            ownerId: "teacher123",
            courseState: "ACTIVE",
            alternateLink: nil
        ))
    }
}
