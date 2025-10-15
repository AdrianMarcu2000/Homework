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

    /// Binding to the currently selected item
    @Binding var selectedItem: Item?

    /// View model for homework capture operations
    var viewModel: HomeworkCaptureViewModel

    /// Show settings sheet
    @State private var showSettings = false

    /// Track which sections are expanded
    @State private var expandedSections: Set<String> = []

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

    /// Deletes homework items from a specific subject section
    ///
    /// - Parameters:
    ///   - subject: The subject section
    ///   - offsets: The index set of items to delete within that section
    private func deleteItemsInSection(subject: String, offsets: IndexSet) {
        withAnimation {
            guard let sectionItems = groupedItems[subject] else { return }
            let itemsToDelete = offsets.map { sectionItems[$0] }

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
    @State private var selectedTab = 0
    @State private var isReanalyzing = false

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
                    if isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress {
                        // Show progress indicator during reanalysis
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
                    } else if let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text("✏️ Exercises")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                ForEach(analysis.exercises, id: \.exerciseNumber) { exercise in
                                    ExerciseCard(exercise: exercise, homeworkItem: item)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                        .id(item.analysisJSON ?? "")
                    } else {
                        // No analysis exists - show image and analyze options
                        ScrollView {
                            VStack(spacing: 20) {
                                if let imageData = item.imageData,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                        .shadow(radius: 5)
                                        .padding()
                                } else {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                }

                                Text("No Analysis Yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 16) {
                                    Button(action: {
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                                    }) {
                                        VStack(spacing: 8) {
                                            Image(systemName: "brain.head.profile")
                                                .font(.title2)
                                            Text("Analyze with Apple")
                                                .font(.headline)
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                    }

                                    Button(action: {
                                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                                    }) {
                                        VStack(spacing: 8) {
                                            Image(systemName: "sparkles")
                                                .font(.title2)
                                            Text("Analyze with Cloud")
                                                .font(.headline)
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.purple)
                                        .cornerRadius(10)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding()
                        }
                    }
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Local reanalyze button
                    Button(action: {
                        isReanalyzing = true
                        viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                    }) {
                        Label("Local", systemImage: "brain.head.profile")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)

                    // Cloud reanalyze button (only show if enabled in settings)
                    if useCloudAnalysis {
                        Button(action: {
                            isReanalyzing = true
                            viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                        }) {
                            Label("Cloud", systemImage: "sparkles")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                    }
                }
            }
        }
    }

    // MARK: - Text Analysis

    /// Analyze text-only homework using AI (no image available)
    private func analyzeTextOnly(text: String) {
        print("🔍 Starting AI text analysis for local homework...")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    print("✅ Text analysis complete - Found \(analysis.exercises.count) exercises")

                    // Save the analysis
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = .prettyPrinted
                        let jsonData = try encoder.encode(analysis)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            self.item.analysisJSON = jsonString
                            try self.viewContext.save()
                            print("✅ Text-only analysis saved to Core Data")
                        }
                    } catch {
                        print("❌ Error saving text-only analysis: \(error)")
                    }

                case .failure(let error):
                    print("❌ Text analysis failed: \(error.localizedDescription)")
                }
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
