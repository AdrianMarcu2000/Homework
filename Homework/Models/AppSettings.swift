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
    @AppStorage("hasCloudSubscription") var hasCloudSubscription: Bool = false {
        didSet {
            // If subscription becomes inactive, automatically disable cloud analysis
            if !hasCloudSubscription && useCloudAnalysis {
                useCloudAnalysis = false
            }
        }
    }

    private init() {}
}
