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

@main
struct HomeworkApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authService = BiometricAuthService.shared

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Configure App Check for security
        AppCheckConfiguration.configure()

        print("🔥 Firebase and App Check initialized")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authService)
        }
    }
}

/// Root view that handles authentication gate
struct RootView: View {
    @EnvironmentObject var authService: BiometricAuthService
    @Environment(\.scenePhase) private var scenePhase

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
}
