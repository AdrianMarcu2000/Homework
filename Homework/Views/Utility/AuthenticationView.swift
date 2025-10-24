//
//  AuthenticationView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import OSLog

/// View that presents authentication screen before allowing app access
struct AuthenticationView: View {
    @ObservedObject var authService = BiometricAuthService.shared
    @State private var isAuthenticating = false
    @State private var showError = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // App icon or logo
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(radius: 10)

                Text("Homework")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                // Authentication prompt
                VStack(spacing: 16) {
                    Image(systemName: authService.biometricType().icon)
                        .font(.system(size: 50))
                        .foregroundColor(.white)

                    Text("Unlock to Continue")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("Use \(authService.biometricType().description) to access your homework")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 30)

                // Authenticate button
                Button(action: authenticate) {
                    HStack(spacing: 12) {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: authService.biometricType().icon)
                                .font(.title3)
                        }

                        Text(isAuthenticating ? "Authenticating..." : "Authenticate")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(radius: 5)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)

                if showError, let error = authService.authenticationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
        }
        .onAppear {
            // Automatically trigger authentication on appear
            authenticate()
        }
    }

    private func authenticate() {
        isAuthenticating = true
        showError = false

        authService.authenticate { success, error in
            isAuthenticating = false

            if !success {
                showError = true
                if let error = error {
                    AppLogger.auth.error("Authentication failed", error: error)
                } else {
                    AppLogger.auth.error("Authentication failed - Unknown error")
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
