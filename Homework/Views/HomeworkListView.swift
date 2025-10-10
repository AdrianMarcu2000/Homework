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

    /// Callback triggered when the camera button is tapped
    var onTakePhoto: () -> Void

    /// Callback triggered when the photo library button is tapped
    var onChooseFromLibrary: () -> Void

    /// Binding to the currently selected item
    @Binding var selectedItem: Item?

    /// View model for homework capture operations
    var viewModel: HomeworkCaptureViewModel

    /// Show settings sheet
    @State private var showSettings = false

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
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    EditButton()

                    Button(action: { showSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: onTakePhoto) {
                        Label("Camera", systemImage: "camera")
                            .labelStyle(.iconOnly)
                    }

                    Button(action: onChooseFromLibrary) {
                        Label("Library", systemImage: "photo")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Private Methods

    /// Deletes homework items at the specified offsets from Core Data.
    ///
    /// - Parameter offsets: The index set of items to delete from the list
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            let itemsToDelete = offsets.map { items[$0] }

            // Check if currently selected item is being deleted
            if let selected = selectedItem, itemsToDelete.contains(selected) {
                selectedItem = nil
            }

            itemsToDelete.forEach(viewContext.delete)

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

                if let timestamp = item.timestamp {
                    Text(timestamp, formatter: itemFormatter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// A detail view for displaying a single homework item's information.
struct HomeworkDetailView: View {
    let item: Item
    var viewModel: HomeworkCaptureViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Custom tab buttons
            HStack(spacing: 0) {
                TabButton(title: "Image", icon: "photo", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "Exercises", icon: "pencil.circle.fill", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemBackground))

            // Tab content
            TabView(selection: $selectedTab) {
                // Image Tab
                Group {
                    if let imageData = item.imageData,
                       let uiImage = UIImage(data: imageData) {
                        ScrollView {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding()
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Image")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .tag(0)

                // Exercises Tab
                Group {
                    if let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("✏️ Exercises")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                ForEach(Array(analysis.exercises.enumerated()), id: \.offset) { index, exercise in
                                    ExerciseCard(exercise: exercise, homeworkItem: item)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Exercises")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Homework Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Homework Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let timestamp = item.timestamp {
                        Text(timestamp, formatter: itemFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                    }) {
                        Label("Re-analyze (Local)", systemImage: "arrow.clockwise")
                    }

                    // Only show cloud option if enabled in settings
                    if useCloudAnalysis {
                        Button(action: {
                            viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                        }) {
                            Label("Re-analyze (Cloud)", systemImage: "cloud")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .disabled(viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
            }
        }
    }
}

/// Custom tab button for inline tab bar with liquid glass style
private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    ZStack {
                        // Liquid glass background
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.ultraThinMaterial)

                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        // Border
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
    let mockViewModel = HomeworkCaptureViewModel(context: PersistenceController.preview.container.viewContext)

    NavigationView {
        HomeworkListView(
            onTakePhoto: {},
            onChooseFromLibrary: {},
            selectedItem: .constant(nil),
            viewModel: mockViewModel
        )
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
