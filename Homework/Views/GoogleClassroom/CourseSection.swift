
//
//  CourseSection.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

// MARK: - Course Section (Disclosure Group)

struct CourseSection: View {
    let course: ClassroomCourse
    let isExpanded: Bool
    let coursework: [ClassroomCoursework]
    let statusFilters: Set<AssignmentStatus>
    @Binding var assignments: [String: ClassroomAssignment]
    @Binding var expandedAssignments: Set<String>
    let onToggle: () -> Void
    let onSelectAssignment: (ClassroomAssignment) -> Void
    let onSelectAttachment: (Material) -> Void

    // Helper to get or create assignment wrapper
    private func getOrCreateAssignment(for courseworkItem: ClassroomCoursework) -> ClassroomAssignment {
        if let existing = assignments[courseworkItem.id] {
            return existing
        } else {
            let newAssignment = ClassroomAssignment(coursework: courseworkItem, courseName: course.name)
            DispatchQueue.main.async {
                if assignments[courseworkItem.id] == nil {
                    assignments[courseworkItem.id] = newAssignment
                    Task {
                        await newAssignment.syncStatusWithGoogleClassroom()
                    }
                }
            }
            return newAssignment
        }
    }

    // Filter coursework by status
    private var filteredCoursework: [ClassroomCoursework] {
        guard !statusFilters.isEmpty else { return [] }

        return coursework.filter { courseworkItem in
            if let assignment = assignments[courseworkItem.id] {
                return statusFilters.contains(assignment.status)
            } else {
                // Create assignment asynchronously, show initially (will filter after sync)
                let _ = getOrCreateAssignment(for: courseworkItem)
                return true
            }
        }
    }

    // Computed properties to avoid state modification warnings
    private var emptyStateIcon: String {
        statusFilters.isEmpty ? "line.3.horizontal.decrease.circle.slash" : "checkmark.circle"
    }

    private var emptyStateText: String {
        statusFilters.isEmpty ? "Select a status filter" : "No matching assignments"
    }

    var body: some View {
        let filtered = filteredCoursework

        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { _ in onToggle() }
            )
        ) {
            // Coursework items
            if filtered.isEmpty {
                HStack {
                    Image(systemName: emptyStateIcon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(emptyStateText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            } else {
                ForEach(filtered.sorted(by: { (a, b) -> Bool in
                    // Sort by due date (most urgent first)
                    guard let dateA = a.dueDate?.date, let dateB = b.dueDate?.date else {
                        return false
                    }
                    return dateA < dateB
                })) { courseworkItem in
                    let assignment = getOrCreateAssignment(for: courseworkItem)
                    let hasAttachments = courseworkItem.materials?.isEmpty == false

                    if hasAttachments {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedAssignments.contains(courseworkItem.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedAssignments.insert(courseworkItem.id)
                                    } else {
                                        expandedAssignments.remove(courseworkItem.id)
                                    }
                                }
                            )
                        ) {
                            // Show attachments
                            if let materials = courseworkItem.materials {
                                ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                                    AttachmentRowCompact(
                                        material: material,
                                        onSelect: { onSelectAttachment(material) }
                                    )
                                    .padding(.leading, 20)
                                }
                            }
                        } label: {
                            Button(action: {
                                onSelectAssignment(assignment)
                            }) {
                                AssignmentRowCompactView(assignmentWrapper: assignment)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: {
                            onSelectAssignment(assignment)
                        }) {
                            AssignmentRowCompactView(assignmentWrapper: assignment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            CourseRowCompact(course: course)
        }
    }
}
