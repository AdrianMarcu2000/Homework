//
//  HomeworkToolbarTitle.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Shared toolbar title view for homework items
struct HomeworkToolbarTitle<Homework: AnalyzableHomework>: View {
    var homework: Homework

    var body: some View {
        VStack(spacing: 2) {
            Text(homework.title)
                .font(.headline)
                .fontWeight(.semibold)
            if let date = homework.date {
                Text(date, formatter: itemFormatter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
