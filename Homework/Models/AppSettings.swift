//
//  AppSettings.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation
import SwiftUI
import Combine

/// Manages app settings and preferences
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("useCloudAnalysis") var useCloudAnalysis: Bool = false

    private init() {}
}
