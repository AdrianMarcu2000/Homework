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
                    // Apple Intelligence availability (read-only, based on Apple's device support)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple Intelligence")
                                .font(.body)
                            Text(AIAnalysisService.shared.isModelAvailable ? "Available on this device" : "Not available on this device")
                                .font(.caption)
                                .foregroundColor(AIAnalysisService.shared.isModelAvailable ? .green : .secondary)
                        }

                        Spacer()

                        Toggle("", isOn: .constant(AIAnalysisService.shared.isModelAvailable))
                            .disabled(true)
                            .labelsHidden()
                    }

                    Toggle("Use cloud analysis", isOn: $useCloudAnalysis)
                        .disabled(!AIAnalysisService.shared.isModelAvailable && useCloudAnalysis == false)

                    HStack {
                        Image(systemName: useCloudAnalysis ? "cloud.fill" : AIAnalysisService.shared.isModelAvailable ? "iphone" : "doc.text.viewfinder")
                            .foregroundColor(useCloudAnalysis ? .blue : AIAnalysisService.shared.isModelAvailable ? .gray : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            if useCloudAnalysis {
                                Text("Using Cloud AI")
                                    .font(.subheadline)
                                Text("Multimodal Gemini AI analysis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if AIAnalysisService.shared.isModelAvailable {
                                Text("Using On-Device AI")
                                    .font(.subheadline)
                                Text("Apple Intelligence (text-only)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Using OCR Only")
                                    .font(.subheadline)
                                Text("Basic text extraction, no AI")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Homework Analysis")
                } footer: {
                    if AIAnalysisService.shared.isModelAvailable && useCloudAnalysis {
                        Text("Cloud AI provides multimodal analysis with much better clarity and exercise detection compared to Apple Intelligence, which currently supports text-only processing.\n\nNote: Cloud analysis will require a subscription in future updates.")
                    } else if AIAnalysisService.shared.isModelAvailable && !useCloudAnalysis {
                        Text("Apple Intelligence provides privacy-focused on-device analysis but is currently text-only (not multimodal). For better clarity and exercise detection, consider upgrading to Cloud AI.\n\nNote: Cloud analysis will require a subscription in future updates.")
                    } else if !AIAnalysisService.shared.isModelAvailable && useCloudAnalysis {
                        Text("Cloud AI uses Google's Gemini AI for multimodal exercise detection and intelligent splitting.\n\nNote: Cloud analysis will require a subscription in future updates.")
                    } else {
                        Text("Apple Intelligence is not available on this device. Without cloud analysis, homework is processed with basic OCR text extraction only. All text appears as a single exercise with no AI-powered splitting.\n\nUpgrade to Cloud AI for intelligent exercise detection.\n\nNote: Cloud analysis will require a subscription in future updates.")
                    }
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
