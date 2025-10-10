//
//  BiometricAuthService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation
import LocalAuthentication
import Combine

/// Service for handling biometric and passcode authentication
@MainActor
class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    @Published var isAuthenticated = false
    @Published var authenticationError: String?

    private init() {}

    /// Check what biometric authentication is available
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    /// Authenticate the user with biometrics or device passcode
    nonisolated func authenticate(completion: @escaping @MainActor (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        // Check if biometric authentication is available
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // Use deviceOwnerAuthentication which falls back to passcode if biometrics fail
        let policy: LAPolicy = canEvaluate ? .deviceOwnerAuthentication : .deviceOwnerAuthentication

        let reason = "Authenticate to access your homework"

        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            Task { @MainActor in
                if success {
                    self.isAuthenticated = true
                    self.authenticationError = nil
                    completion(true, nil)
                } else {
                    self.isAuthenticated = false
                    self.authenticationError = error?.localizedDescription
                    completion(false, error)
                }
            }
        }
    }

    /// Reset authentication state (for logout/lock)
    func lock() {
        self.isAuthenticated = false
    }
}

/// Types of biometric authentication available
enum BiometricType {
    case faceID
    case touchID
    case none

    var description: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "Passcode"
        }
    }

    var icon: String {
        switch self {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock.fill"
        }
    }
}
