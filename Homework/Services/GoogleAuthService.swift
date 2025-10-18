//
//  GoogleAuthService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation
import GoogleSignIn
import Combine

/// Service for managing Google Sign-In authentication with persistent sessions
@MainActor
class GoogleAuthService: ObservableObject {
    static let shared = GoogleAuthService()

    // MARK: - Published Properties

    @Published var currentUser: GIDGoogleUser?
    @Published var isSignedIn = false
    @Published var errorMessage: String?

    // MARK: - Configuration

    private let clientID = "1093713878705-ren052j7epl4g2u4ipq1pfs318n8bcn2.apps.googleusercontent.com" 

    // Required scopes for Google Classroom and Drive
    private let scopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.student-submissions.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.students.readonly",
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/drive.file"
    ]

    private init() {
        configureGoogleSignIn()
    }

    // MARK: - Configuration

    /// Configure Google Sign-In with client ID and scopes
    private func configureGoogleSignIn() {
        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        print("✅ Google Sign-In configured with client ID: \(clientID.prefix(20))...")
    }

    // MARK: - Public Methods

    /// Check if user has a previous session and restore it
    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            Task { @MainActor in
                if let error = error {
                    print("⚠️ No previous sign-in found: \(error.localizedDescription)")
                    self.isSignedIn = false
                    self.currentUser = nil
                    return
                }

                if let user = user {
                    print("✅ Restored previous Google sign-in for: \(user.profile?.email ?? "unknown")")
                    self.currentUser = user
                    self.isSignedIn = true

                    // Refresh token if needed
                    self.refreshTokenIfNeeded()
                } else {
                    self.isSignedIn = false
                }
            }
        }
    }

    /// Sign in with Google
    nonisolated func signIn(presentingViewController: UIViewController) {
        Task { @MainActor in
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingViewController,
                    hint: nil,
                    additionalScopes: scopes
                )

                self.currentUser = result.user
                self.isSignedIn = true
                self.errorMessage = nil

                // Silent sign-in success

            } catch {
                print("❌ Sign-in error: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isSignedIn = false
            }
        }
    }

    /// Sign out from Google
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.currentUser = nil
        self.isSignedIn = false
        print("👋 Signed out from Google")
    }

    /// Get current access token (refresh if expired)
    nonisolated func getAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = await self.currentUser else {
            throw GoogleAuthError.notSignedIn
        }

        // Force refresh if requested or check if token needs refresh
        if forceRefresh || (user.accessToken.expirationDate.map { $0 < Date() } ?? true) {
            return try await refreshAccessToken()
        }

        return user.accessToken.tokenString
    }

    /// Refresh the access token
    nonisolated func refreshAccessToken() async throws -> String {
        guard let user = await self.currentUser else {
            throw GoogleAuthError.notSignedIn
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let user = user {
                    Task { @MainActor in
                        self.currentUser = user
                    }
                    continuation.resume(returning: user.accessToken.tokenString)
                } else {
                    continuation.resume(throwing: GoogleAuthError.tokenRefreshFailed)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Refresh token if it's about to expire
    private func refreshTokenIfNeeded() {
        guard let user = currentUser else { return }

        // Refresh if token expires in less than 5 minutes
        if let expirationDate = user.accessToken.expirationDate,
           expirationDate.timeIntervalSinceNow < 300 {

            Task {
                do {
                    _ = try await refreshAccessToken()
                    print("🔄 Access token refreshed")
                } catch {
                    print("❌ Failed to refresh token: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Error Types

enum GoogleAuthError: LocalizedError {
    case notSignedIn
    case tokenRefreshFailed
    case configurationError

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "User is not signed in to Google"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .configurationError:
            return "Google Sign-In configuration error"
        }
    }
}
