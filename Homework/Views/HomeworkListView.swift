//
//  HomeworkListView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// A view that displays a list of homework items with editing capabilities.
///
/// This view handles the presentation of homework items in a list format,
/// allowing users to select, view, and delete items.
struct HomeworkListView: View {
    // MARK: - Properties

    /// Fetched results containing all homework items sorted by timestamp
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    /// Core Data managed object context
    @Environment(\.managedObjectContext) private var viewContext

    /// Callback triggered when the add homework button is tapped
    var onAddHomework: () -> Void

    // MARK: - Body

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    HomeworkDetailView(item: item)
                } label: {
                    HomeworkRowView(item: item)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .buttonStyle(GlassmorphicButtonStyle())
            }
            ToolbarItem {
                Button(action: onAddHomework) {
                    Label("Add Homework", systemImage: "camera")
                }
                .buttonStyle(GlassmorphicButtonStyle())
            }
        }
        .navigationTitle("Homework")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.15, green: 0.15, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Private Methods

    /// Deletes homework items at the specified offsets from Core Data.
    ///
    /// - Parameter offsets: The index set of items to delete from the list
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

/// A row view displaying a single homework item in the list.
struct HomeworkRowView: View {
    let item: Item

    var body: some View {
        Text(item.timestamp!, formatter: itemFormatter)
    }
}

/// A detail view for displaying a single homework item's information.
struct HomeworkDetailView: View {
    let item: Item

    var body: some View {
        Text("Item at \(item.timestamp!, formatter: itemFormatter)")
            .navigationTitle("Details")
    }
}

// MARK: - Helper Formatters

/// Date formatter used to display homework item timestamps
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

// MARK: - Previews

#Preview {
    NavigationView {
        HomeworkListView(onAddHomework: {})
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
