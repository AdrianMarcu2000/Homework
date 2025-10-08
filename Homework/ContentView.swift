//
//  ContentView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// Main container view of the Homework app that orchestrates the presentation
/// of child views and manages the homework capture workflow.
///
/// This view follows the composite pattern by delegating responsibilities to:
/// - `HomeworkListView`: Displays the list of homework items
/// - `OCRResultView`: Shows OCR text extraction results
/// - `ImagePicker`: Handles camera/photo library access
/// - `HomeworkCaptureViewModel`: Manages business logic and state
struct ContentView: View {
    // MARK: - Properties

    /// Core Data managed object context for database operations
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Body

    var body: some View {
        ContentViewInternal()
            .environment(\.managedObjectContext, viewContext)
    }
}

/// Internal view that has access to the environment's managed object context
private struct ContentViewInternal: View {
    /// Core Data managed object context from environment
    @Environment(\.managedObjectContext) private var viewContext

    /// View model managing homework capture state and logic
    @StateObject private var viewModel: HomeworkCaptureViewModel

    /// Currently selected homework item for detail view
    @State private var selectedItem: Item?

    init() {
        // Initialize with a temporary context; will use environment context
        _viewModel = StateObject(wrappedValue: HomeworkCaptureViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        NavigationView {
            HomeworkListView(
                onAddHomework: viewModel.showImageSourceSelection,
                selectedItem: $selectedItem
            )
            .environment(\.managedObjectContext, viewContext)

            // Main body content
            if let item = selectedItem {
                HomeworkDetailView(item: item)
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a homework item")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("or tap the camera button to add new homework")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .confirmationDialog("Add Homework", isPresented: $viewModel.showActionSheet) {
            Button("Take Photo", action: viewModel.selectCamera)
            Button("Choose from Library", action: viewModel.selectPhotoLibrary)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePicker(
                selectedImage: $viewModel.selectedImage,
                sourceType: viewModel.imageSourceType
            )
        }
        .onChange(of: viewModel.selectedImage) { oldValue, newValue in
            if let image = newValue {
                viewModel.performOCR(on: image)
            }
        }
        .sheet(isPresented: $viewModel.showTextSheet) {
            OCRResultView(
                extractedText: viewModel.extractedText,
                isProcessing: viewModel.isProcessingOCR,
                onSave: { viewModel.saveHomework(context: viewContext) },
                onCancel: viewModel.dismissTextSheet
            )
        }
    }
}

// MARK: - Previews

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
