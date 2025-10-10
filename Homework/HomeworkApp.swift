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

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Configure App Check for security
        AppCheckConfiguration.configure()

        print("🔥 Firebase and App Check initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
