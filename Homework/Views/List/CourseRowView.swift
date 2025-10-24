
//
//  CourseRowView.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

// MARK: - Compact Course Row

struct CourseRowView: View {
    let course: ClassroomCourse

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.headline)

                if let section = course.section, !section.isEmpty {
                    Text(section)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
