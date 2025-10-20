//
//  SettingsView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import OSLog

/// Settings view for app preferences and security
struct SettingsView: View {
    @EnvironmentObject var authService: BiometricAuthService
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var googleAuthService = GoogleAuthService.shared

    @AppStorage("requireAuthentication") private var requireAuthentication = true
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var showingSubscription = false

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
                        .onChange(of: requireAuthentication) { _, newValue in
                            AppLogger.ui.info("User \(newValue ? "enabled" : "disabled") authentication requirement")
                        }

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

                    // Cloud AI Subscription Status
                    if case .subscribed(let expirationDate) = subscriptionService.subscriptionStatus {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud AI Active")
                                        .font(.body)
                                    if let date = expirationDate {
                                        Text("Renews \(date.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Manage") {
                                    showingSubscription = true
                                }
                                .font(.subheadline)
                            }
                        }

                        Toggle("Use cloud analysis", isOn: $useCloudAnalysis)
                            .onChange(of: useCloudAnalysis) { _, newValue in
                                AppLogger.ui.info("User \(newValue ? "enabled" : "disabled") cloud analysis")
                            }
                    } else {
                        Button(action: {
                            AppLogger.ui.info("User opened subscription view")
                            showingSubscription = true
                        }) {
                            HStack {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Subscribe to Cloud AI")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text("$4.99/month")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }

                        Toggle("Use cloud analysis", isOn: $useCloudAnalysis)
                            .disabled(true)
                    }

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
                    if !subscriptionService.subscriptionStatus.isActive {
                        Text("Cloud AI requires an active subscription. Subscribe to enable multimodal analysis with Google's Gemini AI for better clarity and exercise detection.")
                    } else if AIAnalysisService.shared.isModelAvailable && useCloudAnalysis {
                        Text("Cloud AI provides multimodal analysis with much better clarity and exercise detection compared to Apple Intelligence, which currently supports text-only processing.")
                    } else if AIAnalysisService.shared.isModelAvailable && !useCloudAnalysis {
                        Text("Apple Intelligence provides privacy-focused on-device analysis but is currently text-only (not multimodal). For better clarity and exercise detection, consider enabling Cloud AI.")
                    } else if !AIAnalysisService.shared.isModelAvailable && useCloudAnalysis {
                        Text("Cloud AI uses Google's Gemini AI for multimodal exercise detection and intelligent splitting.")
                    } else {
                        Text("Apple Intelligence is not available on this device. Without cloud analysis, homework is processed with basic OCR text extraction only. All text appears as a single exercise with no AI-powered splitting.\n\nUpgrade to Cloud AI for intelligent exercise detection.")
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

                Section {
                    Button(role: .destructive, action: {
                        googleAuthService.disconnect()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)

                            Text("Disconnect Google Account")
                                .foregroundColor(.red)

                            Spacer()
                        }
                    }
                } header: {
                    Text("Google Classroom")
                } footer: {
                    Text("This will sign you out and revoke all permissions granted to the app. You will need to sign in and grant permissions again to use Google Classroom features.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func lockApp() {
        AppLogger.ui.info("User manually locked the app")
        authService.lock()
    }
}

#Preview {
    SettingsView()
        .environmentObject(BiometricAuthService.shared)
}
