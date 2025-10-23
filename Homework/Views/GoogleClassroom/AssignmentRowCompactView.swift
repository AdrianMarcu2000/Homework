
//
//  AssignmentRowCompactView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI
import OSLog

// MARK: - Compact Assignment Row

struct AssignmentRowCompactView: View {
    @ObservedObject var assignmentWrapper: ClassroomAssignment

    var body: some View {
        HStack(spacing: 8) {
            // Subject indicator - only show if analyzed
            if let subject = assignmentWrapper.subject {
                Image(systemName: subjectIcon(for: subject))
                    .foregroundColor(.blue)
                    .font(.body)
            }

            // Status icon
            Image(systemName: assignmentWrapper.status.iconName)
                .foregroundColor(Color(assignmentWrapper.status.color))
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(assignmentWrapper.coursework.title)
                        .font(.subheadline)
                        .lineLimit(1)

                    // Attachment count badge
                    if let materials = assignmentWrapper.coursework.materials, !materials.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(materials.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if let dueDate = assignmentWrapper.coursework.dueDate?.date {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Due \(dueDate, formatter: AssignmentRowCompactView.dateFormatter)")
                            .font(.caption2)
                    }
                    .foregroundColor(dueDate < Date() ? .red : .secondary)
                }
            }

            Spacer()

            // Sync indicator
            if assignmentWrapper.isSyncingStatus {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 20)
        .onAppear {
            Task {
                await assignmentWrapper.syncStatusWithGoogleClassroom()
            }
        }
    }

    /// Returns an SF Symbol icon name for the given subject
    private func subjectIcon(for subject: String) -> String {
        switch subject.lowercased() {
        case "mathematics", "math":
            return "function"
        case "science":
            return "atom"
        case "history":
            return "clock"
        case "english", "language":
            return "book"
        case "geography":
            return "globe"
        case "physics":
            return "waveform.path"
        case "chemistry":
            return "flask"
        case "biology":
            return "leaf"
        default:
            return "graduationcap"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
