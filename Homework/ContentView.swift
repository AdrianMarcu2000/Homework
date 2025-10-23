//
//  ContentView.swift
//  Homework
//
//  Created by Adrian Marcu on 08.10.2025.
//

import SwiftUI
import CoreData
import OSLog

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

/// A simplified detail view that shows exercises directly without intermediate tabs
private struct HomeworkExercisesDetailView: View {
    @ObservedObject var item: Item
    var viewModel: HomeworkCaptureViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("useCloudAnalysis") private var useCloudAnalysis = false
    @AppStorage("hasCloudSubscription") private var hasCloudSubscription = false
    @State private var isReanalyzing = false
    @State private var showingSettings = false
    @State private var showExercises = false

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
            } else {
                // Split view: Active view takes 75%, inactive sidebar 25%
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Left side: Original content (only shown when not showing exercises)
                        if !showExercises {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .trailing) {
                                    ScrollView {
                                        VStack(spacing: 20) {
                                            // Original image/text
                                            if item.imageData != nil, let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(12)
                                                    .shadow(radius: 5)
                                                    .padding(.horizontal)
                                            } else if let extractedText = item.extractedText, !extractedText.isEmpty {
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Text("Extracted Text")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                        .padding(.horizontal)

                                                    Text(extractedText)
                                                        .font(.body)
                                                        .foregroundColor(.primary)
                                                        .textSelection(.enabled)
                                                        .padding()
                                                        .background(Color(UIColor.secondarySystemBackground))
                                                        .cornerRadius(12)
                                                        .padding(.horizontal)
                                                }
                                            } else {
                                                VStack(spacing: 16) {
                                                    Image(systemName: "doc.text.image")
                                                        .font(.system(size: 48))
                                                        .foregroundColor(.secondary)
                                                    Text("No Content")
                                                        .font(.headline)
                                                        .foregroundColor(.secondary)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 60)
                                            }
                                        }
                                        .padding(.vertical)
                                    }
                                    .frame(width: geometry.size.width)

                                    // Floating Exercises button - right middle (only when not showing exercises)
                                    if let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                                        Button(action: {
                                            AppLogger.ui.info("User opened exercises panel")
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                showExercises = true
                                            }
                                        }) {
                                            HStack(spacing: 10) {
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Exercises")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                    Text("\(analysis.exercises.count) found")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.blue.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(16)
                                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: -2, y: 0)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 24)
                                        .position(x: contentGeometry.size.width - 100, y: contentGeometry.size.height / 2)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
                            .frame(width: geometry.size.width)
                        }

                        // Right side: Exercises panel (full width when showing)
                        if showExercises, let analysis = item.analysisResult, !analysis.exercises.isEmpty {
                            GeometryReader { contentGeometry in
                                ZStack(alignment: .leading) {
                                    ScrollView {
                                        VStack(spacing: 16) {
                                            // Exercises content
                                            LessonsAndExercisesView(analysis: analysis, homeworkItem: item)
                                                .padding(.horizontal, 20)
                                        }
                                        .padding(.bottom)
                                    }
                                    .frame(width: geometry.size.width)
                                    .background(Color(UIColor.systemBackground))

                                    // Back button - aligned to middle-left at same vertical position as Exercises button
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Navigation button
                                        Button(action: {
                                            AppLogger.ui.info("User navigated to original from exercises")
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                showExercises = false
                                            }
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "chevron.left")
                                                    .font(.system(size: 16, weight: .semibold))
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Original")
                                                        .font(.headline)
                                                        .fontWeight(.bold)
                                                    Text("View homework")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 14)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.blue.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(16)
                                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 2, y: 0)
                                        }
                                        .buttonStyle(.plain)

                                        // Compact thumbnail preview
                                        if item.imageData != nil, let imageData = item.imageData, let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxWidth: 120, maxHeight: 100)
                                                .cornerRadius(6)
                                                .shadow(radius: 2)
                                        } else if let extractedText = item.extractedText, !extractedText.isEmpty {
                                            Text(extractedText)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(5)
                                                .padding(8)
                                                .frame(maxWidth: 120, alignment: .leading)
                                                .background(Color(UIColor.secondarySystemBackground))
                                                .cornerRadius(6)
                                        }
                                    }
                                    .padding(.leading, 24)
                                    .position(x: 100, y: contentGeometry.size.height / 2)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: geometry.size.width)
                            .id(item.analysisJSON ?? "")
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        // Apple AI button
                        if item.analysisStatus != .inProgress && AIAnalysisService.shared.isModelAvailable {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: false)
                            }) {
                                Image(systemName: "apple.logo")
                                    .font(.body)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
                        }

                        // Google AI button
                        if useCloudAnalysis && item.analysisStatus != .inProgress {
                            Button(action: {
                                isReanalyzing = true
                                viewModel.reanalyzeHomework(item: item, context: viewContext, useCloud: true)
                            }) {
                                Image(systemName: "cloud")
                                    .font(.body)
                            }
                            .disabled(isReanalyzing || viewModel.isProcessingOCR || viewModel.isCloudAnalysisInProgress)
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
        .id(item.id)  // Reset view state when item changes
    }

    // MARK: - Text Analysis

    /// Analyze text-only homework using AI (no image available)
    private func analyzeTextOnly(text: String) {
        AppLogger.ai.info("Starting text analysis for local homework")

        // Use AI analysis service for text-only homework
        AIAnalysisService.shared.analyzeTextOnly(text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let analysis):
                    AppLogger.ai.info("Text analysis complete - Found \(analysis.exercises.count) exercises")

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
                        AppLogger.persistence.error("Error saving text-only analysis", error: error)
                    }

                case .failure(let error):
                    AppLogger.ai.error("Text analysis failed", error: error)
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

/// View for displaying an attachment in the detail pane
private struct AttachmentDetailView: View {
    let material: Material
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading attachment...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Failed to load attachment")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                attachmentContent
            }
        }
        .onAppear {
            loadAttachment()
        }
        .onChange(of: material.driveFile?.driveFile.id) { _, _ in
            // Clear cached data when switching to a different file
            fileData = nil
            errorMessage = nil
            loadAttachment()
        }
    }

    @ViewBuilder
    private var attachmentContent: some View {
        if let driveFile = material.driveFile?.driveFile {
            driveFileViewer(driveFile)
        } else if let link = material.link {
            linkViewer(link)
        } else if let video = material.youtubeVideo {
            videoViewer(video)
        } else if let form = material.form {
            formViewer(form)
        } else {
            Text("Unsupported attachment type")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        let _ = AppLogger.ui.info("Displaying Drive file: \(driveFile.title), extension: \(fileExtension), hasData: \(fileData != nil)")

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            // Image viewer
            let _ = AppLogger.ui.info("File is image type, fileData size: \(fileData?.count ?? 0) bytes")
            if let fileData = fileData {
                if let image = UIImage(data: fileData) {
                    let _ = AppLogger.ui.info("Image loaded successfully, size: \(image.size)")
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    }
                } else {
                    let _ = AppLogger.image.error("Failed to create UIImage from data")

                    // Log data preview for debugging
                    let previewLength = min(16, fileData.count)
                    let preview = fileData.prefix(previewLength).map { String(format: "%02x", $0) }.joined(separator: " ")
                    let _ = AppLogger.image.info("Image data preview (first \(previewLength) bytes): \(preview)")

                    VStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("Failed to load image")
                            .font(.headline)
                        Text("\(fileData.count) bytes received")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Loading image...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else if fileExtension == "pdf" {
            // PDF viewer
            if let fileData = fileData {
                PDFDetailViewer(pdfData: fileData)
            } else {
                VStack {
                    Spacer()
                    Text("Loading PDF...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else if fileExtension == "odt" {
            // ODT viewer
            if let fileData = fileData {
                ODTDetailViewer(odtData: fileData, fileName: driveFile.title)
            } else {
                VStack {
                    Spacer()
                    Text("Loading ODT...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        } else {
            // Generic file - show info
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text(driveFile.title)
                    .font(.headline)
                if let url = URL(string: driveFile.alternateLink) {
                    SwiftUI.Link("Open in Drive", destination: url)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func linkViewer(_ link: Link) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            if let title = link.title {
                Text(title)
                    .font(.headline)
            }

            Text(link.url)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: link.url) {
                SwiftUI.Link("Open Link", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func videoViewer(_ video: YouTubeVideo) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text(video.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: video.alternateLink) {
                SwiftUI.Link("Watch on YouTube", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func formViewer(_ form: Form) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text(form.title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: form.formUrl) {
                SwiftUI.Link("Open Form", destination: url)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    private func loadAttachment() {
        // Only load Drive files (images and PDFs)
        guard let driveFile = material.driveFile?.driveFile else {
            // Links, videos, and forms don't need loading
            AppLogger.ui.info("Attachment is not a Drive file, skipping download")
            return
        }

        AppLogger.ui.info("Loading Drive file: \(driveFile.title)")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                await MainActor.run {
                    fileData = data
                    isLoading = false
                    AppLogger.ui.info("Successfully loaded \(data.count) bytes for \(driveFile.title)")
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
                AppLogger.google.error("Failed to load attachment", error: error)
            }
        }
    }
}

/// ODT viewer for detail pane
private struct ODTDetailViewer: View {
    let odtData: Data
    let fileName: String
    @State private var content: ODTProcessingService.ODTContent?
    @State private var isProcessing = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Processing ODT document...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Failed to load ODT")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if let content = content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Display extracted text
                        if !content.text.isEmpty {
                            Text(content.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                        }

                        // Display extracted images
                        if !content.images.isEmpty {
                            ForEach(Array(content.images.enumerated()), id: \.offset) { index, image in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Image \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)

                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Empty document")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear {
            processODT()
        }
    }

    private func processODT() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let extractedContent = ODTProcessingService.shared.extractContent(from: odtData) {
                DispatchQueue.main.async {
                    content = extractedContent
                    isProcessing = false
                    AppLogger.image.info("ODT processed: \(extractedContent.text.count) chars, \(extractedContent.images.count) images")
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Could not extract content from ODT file"
                    isProcessing = false
                    AppLogger.image.error("Failed to process ODT document")
                }
            }
        }
    }
}

/// PDF viewer for detail pane
import PDFKit

private struct PDFDetailViewer: View {
    let pdfData: Data

    var body: some View {
        let _ = AppLogger.image.info("PDFDetailViewer: Attempting to load PDF with \(pdfData.count) bytes")

        if let pdfDocument = PDFDocument(data: pdfData) {
            let _ = AppLogger.image.info("PDFDetailViewer: PDF loaded successfully, page count: \(pdfDocument.pageCount)")
            PDFKitDetailView(document: pdfDocument)
        } else {
            let _ = AppLogger.image.error("PDFDetailViewer: Failed to create PDFDocument from data")

            // Log data preview for debugging
            let previewLength = min(16, pdfData.count)
            let preview = pdfData.prefix(previewLength).map { String(format: "%02x", $0) }.joined(separator: " ")
            let _ = AppLogger.image.info("PDF data preview (first \(previewLength) bytes): \(preview)")

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Failed to load PDF")
                    .font(.headline)
                Text("\(pdfData.count) bytes received")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

private struct PDFKitDetailView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
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
