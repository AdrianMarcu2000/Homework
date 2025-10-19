//
//  HomeworkApp.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import FirebaseCore
import FirebaseAppCheck
import OSLog

@main
struct HomeworkApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authService = BiometricAuthService.shared
    @StateObject private var subscriptionService = SubscriptionService.shared

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Configure App Check for security
        AppCheckConfiguration.configure()

        AppLogger.lifecycle.info("Firebase and App Check initialized")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authService)
                .environmentObject(subscriptionService)
        }
    }
}

/// Root view that handles authentication gate
struct RootView: View {
    @EnvironmentObject var authService: BiometricAuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRestoredGoogleSignIn = false

    var body: some View {
        ZStack {
            if authService.isAuthenticated {
                ContentView()
                    .transition(.opacity)
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .task {
            // Restore Google Sign-In session on launch (only once)
            if !hasRestoredGoogleSignIn {
                hasRestoredGoogleSignIn = true
                await restoreGoogleSignIn()
            }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // Lock the app when it goes to background
            authService.lock()
        case .inactive:
            // App is transitioning (e.g., during Face ID prompt)
            break
        case .active:
            // App became active - authentication will be required if locked
            break
        @unknown default:
            break
        }
    }

    /// Restore Google Sign-In session if user was previously signed in
    @MainActor
    private func restoreGoogleSignIn() async {
        GoogleAuthService.shared.restorePreviousSignIn()
    }
}
