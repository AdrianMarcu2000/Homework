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
                    SubjectHeader(subject: subject, count: groupedItems[subject]?.count ?? 0)
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

/// Custom section header for subject groups
private struct SubjectHeader: View {
    let subject: String
    let count: Int

    /// Icon for each subject
    private var subjectIcon: String {
        switch subject.lowercased() {
        case "mathematics", "math":
            return "function"
        case "science":
            return "atom"
        case "history":
            return "clock"
        case "english", "language":
            return "book"
        case "geography":
            return "globe"
        case "physics":
            return "waveform.path"
        case "chemistry":
            return "flask"
        case "biology":
            return "leaf"
        default:
            return "folder"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: subjectIcon)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(subject)
                .font(.headline)
                .fontWeight(.semibold)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// A row view displaying a single homework item in the list.
struct HomeworkRowView: View {
    @ObservedObject var item: Item

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
    @State private var showExercises = false
    @State private var isReanalyzing = false

    // Check if already analyzed
    private var hasAnalysis: Bool {
        item.analysisResult != nil && !(item.analysisResult?.exercises.isEmpty ?? true)
    }

    var body: some View {
        if showExercises && hasAnalysis {
            // Show exercises view
            exercisesView
        } else {
            // Show homework overview with image and analyze buttons
            homeworkOverviewView
        }
    }

    // MARK: - Exercises View

    private var exercisesView: some View {
        VStack(spacing: 0) {
            if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                analysisProgressView
            } else if let analysis = item.analysisResult {
                VStack(spacing: 0) {
                    // Custom navigation bar
                    HStack {
                        Button(action: { showExercises = false }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .padding()

                        Spacer()

                        Text("Exercises")
                            .font(.headline)

                        Spacer()

                        // Invisible button for symmetry
                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .padding()
                        .opacity(0)
                    }
                    .background(Color(UIColor.systemBackground))

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(analysis.exercises, id: \.exerciseNumber) { exercise in
                                ExerciseCard(exercise: exercise, homeworkItem: item)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Analysis Progress

    private var analysisProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            if let progress = viewModel.analysisProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                Text("Analyzing segment \(progress.current) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text(viewModel.isCloudAnalysisInProgress ? "Analyzing with cloud AI..." : "Analyzing homework...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Homework Overview

    private var homeworkOverviewView: some View {
        VStack(spacing: 0) {
            if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                // Show progress
                analysisProgressView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display scanned image in main body
                        if let imageData = item.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding()
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No Image")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }

                        // AI Analysis / Re-analyze buttons
                        VStack(spacing: 12) {
                            Text(hasAnalysis ? "Actions" : "Analyze with AI")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                // Apple AI button
                                if AIAnalysisService.shared.isModelAvailable {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Apple AI")
                                        isReanalyzing = true
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "apple.logo")
                                                .font(.title2)
                                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                                .font(.caption)
                                            if !hasAnalysis {
                                                Text("Apple AI")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, hasAnalysis ? 12 : 16)
                                        .background(Color.purple.opacity(0.1))
                                        .foregroundColor(.purple)
                                        .cornerRadius(10)
                                    }
                                    .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                                }

                                // Google AI button
                                if useCloudAnalysis {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped \(hasAnalysis ? "re-analyze" : "analyze") with Cloud AI")
                                        isReanalyzing = true
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "cloud.fill")
                                                .font(.title2)
                                            Text(hasAnalysis ? "Re-analyze" : "Analyze with")
                                                .font(.caption)
                                            if !hasAnalysis {
                                                Text("Google AI")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, hasAnalysis ? 12 : 16)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(10)
                                    }
                                    .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                                }

                                // View Exercises button (only when analyzed)
                                if hasAnalysis {
                                    Button(action: {
                                        AppLogger.ui.info("User tapped view exercises")
                                        showExercises = true
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "pencil.and.list.clipboard")
                                                .font(.title2)
                                            Text("View Exercises")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Homework Details")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.isProcessingOCR) { _, newValue in
            if !newValue && !viewModel.isCloudAnalysisInProgress {
                isReanalyzing = false
            }
        }
        .onChange(of: viewModel.isCloudAnalysisInProgress) { _, newValue in
            if !newValue && !viewModel.isProcessingOCR {
                isReanalyzing = false
            }
        }
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
        }
    }

    // MARK: - Text Analysis

    /// Analyze text-only homework using AI (no image available)
    private func analyzeTextOnly(text: String) {
        AppLogger.ai.info("Starting text-only AI analysis for local homework")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    AppLogger.ai.info("Text analysis complete with \(analysis.exercises.count) exercises")

                    // Save the analysis
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(analysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            self.item.analysisJSON = jsonString
                            try self.viewContext.save()
                            AppLogger.persistence.info("Text-only analysis saved to Core Data")
                        }
                    } catch {
                        AppLogger.persistence.error("Failed to save text-only analysis", error: error)
                    }

                case .failure(let error):
                    AppLogger.ai.error("Text analysis failed", error: error)
                }
            }
        }
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
            onLoadFile: {},
            onLoadPDF: {},
            selectedItem: .constant(nil),
            viewModel: mockViewModel
        )
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
