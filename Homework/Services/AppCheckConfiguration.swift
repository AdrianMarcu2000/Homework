//
//  AppCheckConfiguration.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

/// Configures Firebase App Check to verify app authenticity
///
/// App Check protects your backend resources from abuse by preventing
/// unauthorized clients from accessing your Firebase services.
class AppCheckConfiguration {
    /// Configures App Check with the appropriate provider based on build configuration
    static func configure() {
        #if DEBUG
        // For local emulator testing, App Check debug tokens don't work on simulators
        // We'll skip App Check setup and use a bypass token in CloudAnalysisService
        print("🔐 App Check: DISABLED for local emulator testing (DEBUG mode)")
        print("⚠️  Note: App Check will be ENABLED in RELEASE builds on physical devices")
        print("💡 To test App Check, build in RELEASE mode on a real iOS device")
        #else
        // Use App Attest for production (iOS 14+)
        // Provides device-level attestation of app authenticity
        let providerFactory = AppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        print("🔐 App Check: Using App Attest Provider for production")
        #endif
    }
}
