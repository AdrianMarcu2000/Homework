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

    /// Binding to the currently selected item
    @Binding var selectedItem: Item?

    // MARK: - Body

    var body: some View {
        List(selection: $selectedItem) {
            ForEach(items) { item in
                HomeworkRowView(item: item)
                    .tag(item)
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
        HStack(spacing: 12) {
            // Thumbnail image
            if let imageData = item.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                // Placeholder if no image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .foregroundColor(.secondary)
                    )
            }

            // Text preview and timestamp
            VStack(alignment: .leading, spacing: 4) {
                if let text = item.extractedText, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("No text extracted")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }

                Text(item.timestamp!, formatter: itemFormatter)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// A detail view for displaying a single homework item's information.
struct HomeworkDetailView: View {
    let item: Item

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with timestamp
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Homework Details")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(item.timestamp!, formatter: itemFormatter)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Side-by-side layout for iPad/large screens, stacked for iPhone
                    if geometry.size.width > 600 {
                        // Horizontal layout for larger screens
                        HStack(alignment: .top, spacing: 20) {
                            // Image on the left
                            if let imageData = item.imageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: geometry.size.width * 0.45)
                                    .cornerRadius(12)
                                    .shadow(radius: 5)
                            }

                            // Analysis content on the right
                            VStack(alignment: .leading, spacing: 16) {
                                if let analysis = item.analysisResult {
                                    LessonsAndExercisesView(analysis: analysis)
                                } else if let text = item.extractedText, !text.isEmpty {
                                    // Fallback to raw text if no analysis
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Extracted Text")
                                            .font(.headline)
                                            .foregroundColor(.secondary)

                                        ScrollView {
                                            Text(text)
                                                .font(.body)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding()
                                        .frame(maxHeight: 500)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Vertical layout for smaller screens
                        VStack(alignment: .leading, spacing: 20) {
                            // Display the scanned image
                            if let imageData = item.imageData,
                               let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .shadow(radius: 5)
                                    .padding(.horizontal)
                            }

                            // Display lessons and exercises or fallback to text
                            if let analysis = item.analysisResult {
                                LessonsAndExercisesView(analysis: analysis)
                                    .padding(.horizontal)
                            } else if let text = item.extractedText, !text.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Extracted Text")
                                        .font(.headline)
                                        .foregroundColor(.secondary)

                                    Text(text)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
        HomeworkListView(
            onAddHomework: {},
            selectedItem: .constant(nil)
        )
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
