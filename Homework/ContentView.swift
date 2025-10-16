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

    /// Currently selected classroom course
    @State private var selectedCourse: ClassroomCourse?

    /// Currently selected classroom assignment
    @State private var selectedAssignment: ClassroomAssignment?

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
                        selectedItem: $selectedItem,
                        viewModel: viewModel
                    )
                } else {
                    GoogleClassroomView(
                        selectedCourse: $selectedCourse,
                        selectedAssignment: $selectedAssignment
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.managedObjectContext, viewContext)

            // Detail view - force refresh when tab changes
            Group {
                if selectedTab == .myHomework {
                    if let item = selectedItem {
                        HomeworkExercisesDetailView(item: item, viewModel: viewModel)
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
                    // Detail view for classroom
                    if let assignment = selectedAssignment {
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
        .onChange(of: viewModel.selectedImage) { oldValue, newValue in
            if let image = newValue {
                viewModel.performOCR(on: image)
            }
        }
        .onReceive(viewModel.$newlyCreatedItem) { newItem in
            if let newItem = newItem {
                selectedItem = newItem
            }
        }
    }
}

/// A simplified detail view that shows exercises directly without intermediate tabs
private struct HomeworkExercisesDetailView: View {
    @ObservedObject var item: Item
    var viewModel: HomeworkCaptureViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @AppStorage("hasCloudSubscription") private var hasCloudSubscription = false
    @State private var isReanalyzing = false
    @State private var showingSettings = false

    /// Determines which AI upgrade button to show based on analysis history and AI availability
    private func getUpgradeOption() -> (show: Bool, method: AnalysisMethod, label: String, icon: String, color: Color, opensSettings: Bool)? {
        let currentMethod = item.usedAnalysisMethod
        let appleAvailable = AIAnalysisService.shared.isModelAvailable
        let cloudEnabled = useCloudAnalysis

        // If already using cloud AI, no upgrade available
        if currentMethod == .cloudAI {
            return nil
        }

        // Case 1: User has subscription and cloud is enabled - show "Analyze with AI"
        if hasCloudSubscription && cloudEnabled {
            // Only show if not already analyzed with cloud
            if currentMethod != .cloudAI {
                return (true, .cloudAI, "Analyze with AI", "cloud.fill", .orange, false)
            }
        }

        // Case 2: User has subscription but cloud is disabled - show "Enable AI" (opens settings)
        if hasCloudSubscription && !cloudEnabled {
            return (true, .cloudAI, "Enable AI", "cloud.fill", .orange, true)
        }

        // Case 3: No subscription - show "Enable AI" (opens settings to subscribe)
        if !hasCloudSubscription && currentMethod != .cloudAI {
            return (true, .cloudAI, "Enable AI", "cloud.fill", .orange, true)
        }

        // Case 4: If Apple AI is available and not used yet, suggest Apple AI
        if appleAvailable && currentMethod != .appleAI && !cloudEnabled {
            return (true, .appleAI, "Analyze with AI", "apple.logo", .orange, false)
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
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
                VStack(spacing: 0) {
                    // Action buttons at the top
                    HStack(spacing: 12) {
                        // View Original button - show image or text
                        if item.imageData != nil {
                            // Has image - show image viewer
                            NavigationLink(destination: HomeworkImageView(item: item)) {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.fill")
                                        .font(.title2)
                                    Text("View Original")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        } else if item.extractedText != nil && !(item.extractedText?.isEmpty ?? true) {
                            // No image but has text - show text viewer
                            NavigationLink(destination: HomeworkTextView(item: item)) {
                                VStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.title2)
                                    Text("View Original")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }

                        // Analyze with Apple Intelligence button
                        if AIAnalysisService.shared.isModelAvailable {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "apple.logo")
                                        .font(.title2)
                                    Text("Apple AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }

                        // Analyze with Google Gemini button or upgrade/enable AI prompt
                        if useCloudAnalysis && item.usedAnalysisMethod == .cloudAI {
                            // Already analyzed with cloud, show cloud reanalysis button
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "cloud.fill")
                                        .font(.title2)
                                    Text("Google AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        } else if let upgrade = getUpgradeOption() {
                            // Show enable/upgrade AI button
                            Button(action: {
                                if upgrade.opensSettings {
                                    // Open settings to enable cloud AI or subscribe
                                    showingSettings = true
                                } else {
                                    // Perform analysis
                                    isReanalyzing = true
                                    viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: upgrade.method == .cloudAI)
                                }
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: upgrade.icon)
                                        .font(.title2)
                                    Text(upgrade.label)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(upgrade.color.opacity(0.1))
                                .foregroundColor(upgrade.color)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    // Exercises content
                    ScrollView {
                        LessonsAndExercisesView(analysis: analysis, homeworkItem: item)
                            .padding()
                    }
                    .id(item.analysisJSON ?? "")
                }
            } else {
                // No analysis exists - show original content and analyze options
                VStack(spacing: 0) {
                    // Action buttons at the top
                    HStack(spacing: 12) {
                        // Analyze with Apple Intelligence button
                        if item.analysisStatus != .inProgress && AIAnalysisService.shared.isModelAvailable {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "apple.logo")
                                        .font(.title2)
                                    Text("Apple AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }

                        // Analyze with Google Gemini button
                        if useCloudAnalysis && item.analysisStatus != .inProgress {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: "cloud.fill")
                                        .font(.title2)
                                    Text("Google AI")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    // Original content
                    ZStack {
                        if item.imageData != nil {
                            HomeworkImageView(item: item)
                        } else {
                            HomeworkTextView(item: item)
                        }

                        if item.analysisStatus == .inProgress {
                            Color.black.opacity(0.4)
                                .edgesIgnoringSafeArea(.all)
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Analyzing...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.top)
                            }
                        }
                    }
                }
            }
        }
        
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
                    Text(item.title)
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(BiometricAuthService.shared)
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

/// A simple view to display the homework image
private struct HomeworkImageView: View {
    let item: Item

    var body: some View {
        ScrollView {
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
                .padding()
            }
        }
        .navigationTitle("Image")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A simple view to display the homework original text
private struct HomeworkTextView: View {
    let item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Show extracted text if available
                if let extractedText = item.extractedText, !extractedText.isEmpty {
                    Text(extractedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Text Available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Original")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Date formatter used to display homework item timestamps
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

// MARK: - Previews

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
