//
//  HomeworkListView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import OSLog

/// A view that displays a list of homework items with editing capabilities.
///
/// This view handles the presentation of homework items in a list format,
/// allowing users to select, view, and delete items.
struct HomeworkListView: View {
    // MARK: - Properties

    /// Fetched results containing all homework items sorted by timestamp (newest first)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
        animation: .default)
    private var items: FetchedResults<Item>

    /// Core Data managed object context
    @Environment(\.managedObjectContext) private var viewContext

    /// Callback triggered when the camera button is tapped
    var onTakePhoto: () -> Void

    /// Callback triggered when the photo library button is tapped
    var onChooseFromLibrary: () -> Void

    /// Callback triggered when the load file button is tapped
    var onLoadFile: () -> Void

    /// Callback triggered when the load PDF button is tapped
    var onLoadPDF: () -> Void

    /// Binding to the currently selected item
    @Binding var selectedItem: Item?

    /// View model for homework capture operations
    var viewModel: HomeworkCaptureViewModel

    /// Show settings sheet
    @State private var showSettings = false

    /// Track which sections are expanded
    @State private var expandedSections: Set<String> = []

    /// Track edit mode
    @Environment(\.editMode) private var editMode

    // MARK: - Body

    /// Grouped items by subject
    private var groupedItems: [String: [Item]] {
        Dictionary(grouping: Array(items), by: { $0.subject })
    }

    /// Sorted subject names by newest homework in each group
    private var sortedSubjects: [String] {
        groupedItems.keys.sorted { subject1, subject2 in
            // "Other" always goes last
            if subject1 == "Other" { return false }
            if subject2 == "Other" { return true }

            // Get newest homework in each subject
            let newest1 = groupedItems[subject1]?.first?.timestamp ?? Date.distantPast
            let newest2 = groupedItems[subject2]?.first?.timestamp ?? Date.distantPast

            // Sort by newest first
            return newest1 > newest2
        }
    }

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(sortedSubjects, id: \.self) { subject in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSections.contains(subject) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedSections.insert(subject)
                            } else {
                                expandedSections.remove(subject)
                            }
                        }
                    )
                ) {
                    ForEach(groupedItems[subject] ?? []) { item in
                        HomeworkRowView(item: item)
                            .tag(item)
                    }
                    .onDelete { offsets in
                        deleteItemsInSection(subject: subject, offsets: offsets)
                    }
                } label: {
                    SubjectHeaderView(subject: subject, count: groupedItems[subject]?.count ?? 0)
                }
            }
        }
        .onAppear {
            // Expand the first section (newest) by default
            if let firstSubject = sortedSubjects.first {
                expandedSections.insert(firstSubject)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    withAnimation {
                        if editMode?.wrappedValue == .active {
                            editMode?.wrappedValue = .inactive
                            AppLogger.ui.info("User exited edit mode")
                        } else {
                            editMode?.wrappedValue = .active
                            AppLogger.ui.info("User entered edit mode")
                        }
                    }
                }) {
                    Text(editMode?.wrappedValue == .active ? "Done" : "Edit")
                        .fontWeight(.medium)
                }
            }

            if editMode?.wrappedValue != .active {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onTakePhoto) {
                        Label("Camera", systemImage: "camera")
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onChooseFromLibrary) {
                        Label("Library", systemImage: "photo")
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onLoadFile) {
                        Label("Load File", systemImage: "folder")
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onLoadPDF) {
                        Label("Load PDF", systemImage: "doc.fill")
                    }
                    .labelStyle(.iconOnly)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Private Methods

    /// Deletes homework items from a specific subject section
    ///
    /// - Parameters:
    ///   - subject: The subject section
    ///   - offsets: The index set of items to delete within that section
    private func deleteItemsInSection(subject: String, offsets: IndexSet) {
        withAnimation {
            guard let sectionItems = groupedItems[subject] else { return }
            let itemsToDelete = offsets.map { sectionItems[$0] }

            AppLogger.ui.info("User deleted \(itemsToDelete.count) homework item(s) from \(subject)")

            // Check if currently selected item is being deleted
            if let selected = selectedItem, itemsToDelete.contains(selected) {
                selectedItem = nil
            }

            itemsToDelete.forEach(viewContext.delete)

            do {
                try viewContext.save()
                AppLogger.persistence.info("Deleted items saved to Core Data")
            } catch {
                AppLogger.persistence.error("Failed to delete homework items", error: error)
                // In production, you might want to show an alert to the user instead of crashing
                // For now, roll back the delete operation
                viewContext.rollback()
            }
        }
    }
}
