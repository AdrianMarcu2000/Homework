//
//  ContentView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData

/// Navigation tabs available in the app
enum AppTab: String, CaseIterable {
    case myHomework = "My Homework"
    case classroom = "Classroom"

    var icon: String {
        switch self {
        case .myHomework: return "book.fill"
        case .classroom: return "graduationcap.fill"
        }
    }
}

/// Main container view of the Homework app that orchestrates the presentation
/// of child views and manages the homework capture workflow.
///
/// This view follows the composite pattern by delegating responsibilities to:
/// - `HomeworkListView`: Displays the list of homework items
/// - `GoogleClassroomView`: Displays Google Classroom courses and assignments
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

    /// Currently selected tab
    @State private var selectedTab: AppTab = .myHomework

    /// Currently selected homework item for detail view
    @State private var selectedItem: Item?

    init() {
        // Initialize with a temporary context; will use environment context
        _viewModel = StateObject(wrappedValue: HomeworkCaptureViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector at the top
                Picker("Section", selection: $selectedTab) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selected tab
                if selectedTab == .myHomework {
                    HomeworkListView(
                        onTakePhoto: viewModel.selectCamera,
                        onChooseFromLibrary: viewModel.selectPhotoLibrary,
                        selectedItem: $selectedItem,
                        viewModel: viewModel
                    )
                } else {
                    GoogleClassroomView()
                }
            }
            .environment(\.managedObjectContext, viewContext)

            // Detail view
            if selectedTab == .myHomework {
                if let item = selectedItem {
                    HomeworkDetailView(item: item, viewModel: viewModel)
                        .environment(\.managedObjectContext, viewContext)
                } else {
                    // Empty state for homework
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Select a homework item")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("or tap the camera/photo buttons to add new homework")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            } else {
                // Empty state for classroom
                VStack(spacing: 16) {
                    Image(systemName: "graduationcap.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a course")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("to view assignments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
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
                analysisProgress: viewModel.analysisProgress,
                isCloudAnalysisInProgress: viewModel.isCloudAnalysisInProgress,
                onSave: { viewModel.saveHomework(context: viewContext) },
                onCancel: viewModel.dismissTextSheet,
                onCloudAnalysis: viewModel.performCloudAnalysis
            )
        }
    }
}

// MARK: - Previews

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
