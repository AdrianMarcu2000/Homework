//
//  SettingsView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI

/// Settings view for app preferences and security
struct SettingsView: View {
    @EnvironmentObject var authService: BiometricAuthService
    @AppStorage("requireAuthentication") private var requireAuthentication = true
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: authService.biometricType().icon)
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Security")
                                .font(.headline)

                            Text("\(authService.biometricType().description) is available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if authService.isAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Authentication")
                }

                Section {
                    Toggle("Require Authentication", isOn: $requireAuthentication)

                    Button(action: lockApp) {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.orange)

                            Text("Lock App Now")
                                .foregroundColor(.primary)

                            Spacer()
                        }
                    }
                    .disabled(!authService.isAuthenticated)
                } footer: {
                    Text("When enabled, you'll need to authenticate with \(authService.biometricType().description) or your device passcode each time you open the app.")
                }

                Section {
                    Toggle("Default to cloud analysis", isOn: $useCloudAnalysis)

                    HStack {
                        Image(systemName: useCloudAnalysis ? "cloud.fill" : "iphone")
                            .foregroundColor(useCloudAnalysis ? .blue : .gray)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(useCloudAnalysis ? "Using Cloud AI" : "Using On-Device AI")
                                .font(.subheadline)
                            Text(useCloudAnalysis ? "Advanced Gemini AI analysis" : "Apple Intelligence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Homework Analysis")
                } footer: {
                    Text("Cloud analysis uses Google's Gemini AI for more detailed exercise detection and smarter input type suggestions. On-device analysis uses Apple Intelligence (requires iOS 18.1+).")
                }

                Section {
                    HStack {
                        Text("App Version")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func lockApp() {
        authService.lock()
    }
}

#Preview {
    SettingsView()
        .environmentObject(BiometricAuthService.shared)
}
