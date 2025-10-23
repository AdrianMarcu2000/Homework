
//
//  ContentView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import OSLog


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
    /// Core Data managed object context from environment
    @Environment(\.managedObjectContext) private var viewContext

    /// View model managing homework capture state and logic
    @StateObject private var viewModel: HomeworkCaptureViewModel

    /// Currently selected tab
    @State private var selectedTab: AppTab = .myHomework

    /// Currently selected homework item for detail view
    @State private var selectedItem: Item?

    /// Currently selected classroom course
    @State private var selectedCourse: ClassroomCourse?

    /// Currently selected classroom assignment
    @State private var selectedAssignment: ClassroomAssignment?

    /// Currently selected attachment to view in detail pane
    @State private var selectedAttachment: Material?

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
                .onChange(of: selectedTab) { _, newTab in
                    // Clear selections when switching tabs
                    if newTab == .classroom {
                        selectedItem = nil
                    } else if newTab == .myHomework {
                        selectedCourse = nil
                        selectedAssignment = nil
                    }
                }

                // Content based on selected tab
                if selectedTab == .myHomework {
                    HomeworkListView(
                        onTakePhoto: viewModel.selectCamera,
                        onChooseFromLibrary: viewModel.selectPhotoLibrary,
                        onLoadFile: viewModel.selectDocumentPicker,
                        onLoadPDF: viewModel.selectPDFPicker,
                        selectedItem: $selectedItem,
                        viewModel: viewModel
                    )
                } else {
                    GoogleClassroomView(
                        selectedCourse: $selectedCourse,
                        selectedAssignment: $selectedAssignment,
                        selectedAttachment: $selectedAttachment
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.managedObjectContext, viewContext)

            // Detail view - force refresh when tab changes
            Group {
                if selectedTab == .myHomework {
                    if let item = selectedItem {
                        // Show PDF viewer for PDF homework, regular view for image homework
                        if item.isPDF {
                            PDFHomeworkView(item: item)
                                .environment(\.managedObjectContext, viewContext)
                        } else {
                            HomeworkExercisesDetailView(item: item, viewModel: viewModel)
                                .environment(\.managedObjectContext, viewContext)
                        }
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
                    // Detail view for classroom
                    if let attachment = selectedAttachment {
                        // Show attachment viewer in detail pane
                        // Use file ID to force view recreation when switching attachments
                        AttachmentDetailView(material: attachment)
                            .id(attachment.driveFile?.driveFile.id ?? UUID().uuidString)
                    } else if let assignment = selectedAssignment {
                        AssignmentDetailView(assignment: assignment)
                    } else {
                        // Empty state for classroom
                        VStack(spacing: 16) {
                            Image(systemName: "graduationcap.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("Select an assignment")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("from a course to view exercises")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .id(selectedTab)
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePicker(
                selectedImage: $viewModel.selectedImage,
                sourceType: viewModel.imageSourceType
            )
        }
        .sheet(isPresented: $viewModel.showDocumentPicker) {
            DocumentPicker(selectedImage: $viewModel.selectedImage)
        }
        .sheet(isPresented: $viewModel.showPDFPicker) {
            PDFPicker(selectedPDFData: $viewModel.selectedPDFData)
        }
        .onChange(of: viewModel.selectedImage) { oldValue, newValue in
            if let image = newValue {
                viewModel.performOCR(on: image)
            }
        }
        .onChange(of: viewModel.selectedPDFData) { oldValue, newValue in
            if newValue != nil {
                viewModel.processPDF()
            }
        }
        .onReceive(viewModel.$newlyCreatedItem) { newItem in
            if let newItem = newItem {
                selectedItem = newItem
            }
        }
    }
}

// MARK: - Previews

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

