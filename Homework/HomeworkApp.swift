//
//  HomeworkApp.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

@main
struct HomeworkApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
