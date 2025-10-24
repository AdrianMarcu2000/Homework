
//
//  SubjectHeader.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Custom section header for subject groups
struct SubjectHeaderView: View {
    let subject: String
    let count: Int

    /// Icon for each subject
    private var subjectIcon: String {
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
            return "folder"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: subjectIcon)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(subject)
                .font(.headline)
                .fontWeight(.semibold)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
