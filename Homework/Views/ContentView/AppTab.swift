
//
//  AppTab.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import SwiftUI

/// Navigation tabs available in the app
enum AppTab: String, CaseIterable {
    case myHomework = "My Homework"
    case classroom = "Classroom"

    var icon: String {
        switch self {
        case .myHomework: return "book.fill"
        case .classroom: return "graduationcap.fill"
        }
    }
}
