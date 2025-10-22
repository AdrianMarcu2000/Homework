//
//  GoogleClassroomView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import GoogleSignIn
import OSLog
import PDFKit

// Type alias to disambiguate from SwiftUI.Link
typealias ClassroomLink = Link

/// View for Google Classroom integration with tree structure navigation
struct GoogleClassroomView: View {
    @StateObject private var authService = GoogleAuthService.shared
    @State private var courses: [ClassroomCourse] = []
    @State private var courseworkByID: [String: [ClassroomCoursework]] = [:]
    @State private var assignments: [String: ClassroomAssignment] = [:]
    @State private var expandedCourses: Set<String> = []
    @State private var expandedAssignments: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var statusFilters: Set<AssignmentStatus> = Set(AssignmentStatus.allCases)

    @Binding var selectedCourse: ClassroomCourse?
    @Binding var selectedAssignment: ClassroomAssignment?
    @Binding var selectedAttachment: Material?

    var body: some View {
        Group {
            if authService.isSignedIn {
                // Show courses tree
                coursesTreeView
            } else {
                // Show sign-in prompt
                signInPromptView
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if authService.isSignedIn && !courses.isEmpty {
                    Menu {
                        Button(action: {
                            if statusFilters.isEmpty {
                                statusFilters = Set(AssignmentStatus.allCases)
                            } else {
                                statusFilters.removeAll()
                            }
                        }) {
                            HStack {
                                Image(systemName: statusFilters.isEmpty ? "checkmark.square" : "square")
                                Text(statusFilters.isEmpty ? "Select All" : "Clear All")
                            }
                        }

                        Divider()

                        ForEach(AssignmentStatus.allCases, id: \.self) { status in
                            Button(action: {
                                if statusFilters.contains(status) {
                                    statusFilters.remove(status)
                                } else {
                                    statusFilters.insert(status)
                                }
                                AppLogger.ui.info("User toggled filter: \(status.displayName)")
                            }) {
                                HStack {
                                    Image(systemName: statusFilters.contains(status) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(Color(status.color))
                                    Image(systemName: status.iconName)
                                        .foregroundColor(Color(status.color))
                                    Text(status.displayName)
                                        .foregroundColor(Color(status.color))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if !statusFilters.isEmpty {
                                Text("\(statusFilters.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .help("Filter by status")
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
        .onAppear {
            if authService.isSignedIn {
                loadCourses()
            }
        }
    }

    // MARK: - Sign In View

    private var signInPromptView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "graduationcap.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Google Classroom")
                .font(.title)
                .fontWeight(.bold)

            Text("Sign in to view your courses and assignments")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: signIn) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title3)

                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }

    // MARK: - Courses Tree View

    private var coursesTreeView: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                if isLoading && courses.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading courses...")
                        Spacer()
                    }
                } else if courses.isEmpty {
                    VStack {
                        Spacer()
                        emptyStateView
                        Spacer()
                    }
                } else {
                    List(selection: $selectedAssignment) {
                        ForEach(courses.filter { $0.isActive }) { course in
                            CourseSection(
                                course: course,
                                isExpanded: expandedCourses.contains(course.id),
                                coursework: courseworkByID[course.id] ?? [],
                                statusFilters: statusFilters,
                                assignments: $assignments,
                                expandedAssignments: $expandedAssignments,
                                onToggle: {
                                    toggleCourse(course)
                                },
                                onSelectAssignment: { assignment in
                                    selectedAttachment = nil // Clear attachment when selecting assignment
                                    selectedAssignment = assignment
                                },
                                onSelectAttachment: { attachment in
                                    selectedAssignment = nil // Clear assignment when selecting attachment
                                    selectedAttachment = attachment
                                }
                            )
                        }
                    }
                    .listStyle(.sidebar)
                    .refreshable {
                        loadCourses()
                    }
                }
            }

            // Login status and sign out - always at bottom
            VStack(spacing: 0) {
                Divider()

                // Logged in status
                if let email = authService.currentUser?.profile?.email {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.green)
                        Text("Logged in as")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(email)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                }

                // Sign out button
                Button(role: .destructive, action: signOut) {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                    }
                }
                .padding(.vertical, 12)
                .background(Color(UIColor.systemBackground))
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Courses Found")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("You don't have any active courses yet")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: loadCourses) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Actions

    private func signIn() {
        AppLogger.google.info("User initiated Google sign-in")
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            AppLogger.google.error("Could not find root view controller", error: NSError(domain: "GoogleClassroom", code: -1))
            return
        }

        authService.signIn(presentingViewController: rootViewController)
    }

    private func signOut() {
        AppLogger.google.info("User signed out of Google Classroom")
        authService.signOut()
        courses = []
        courseworkByID = [:]
        expandedCourses = []
    }
    private func loadCourses() {
        AppLogger.google.info("Loading Google Classroom courses")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                courses = try await GoogleClassroomService.shared.fetchCourses()
                isLoading = false
                AppLogger.google.info("Loaded \(courses.count) courses successfully")
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                AppLogger.google.error("Failed to load courses", error: error)
            }
        }
    }

    private func toggleCourse(_ course: ClassroomCourse) {
        if expandedCourses.contains(course.id) {
            expandedCourses.remove(course.id)
            AppLogger.ui.info("User collapsed course: \(course.name)")
        } else {
            expandedCourses.insert(course.id)
            AppLogger.ui.info("User expanded course: \(course.name)")
            // Load coursework if not already loaded
            if courseworkByID[course.id] == nil {
                loadCoursework(for: course)
            }
        }
    }

    private func loadCoursework(for course: ClassroomCourse) {
        AppLogger.google.info("Loading coursework for course: \(course.name)")
        Task {
            do {
                let coursework = try await GoogleClassroomService.shared.fetchCoursework(for: course.id)
                await MainActor.run {
                    courseworkByID[course.id] = coursework
                    AppLogger.google.info("Loaded \(coursework.count) assignments for \(course.name)")
                }
            } catch {
                AppLogger.google.error("Failed to load coursework for \(course.name)", error: error)
            }
        }
    }
}

// MARK: - Course Section (Disclosure Group)

struct CourseSection: View {
    let course: ClassroomCourse
    let isExpanded: Bool
    let coursework: [ClassroomCoursework]
    let statusFilters: Set<AssignmentStatus>
    @Binding var assignments: [String: ClassroomAssignment]
    @Binding var expandedAssignments: Set<String>
    let onToggle: () -> Void
    let onSelectAssignment: (ClassroomAssignment) -> Void
    let onSelectAttachment: (Material) -> Void

    // Helper to get or create assignment wrapper
    private func getOrCreateAssignment(for courseworkItem: ClassroomCoursework) -> ClassroomAssignment {
        if let existing = assignments[courseworkItem.id] {
            return existing
        } else {
            let newAssignment = ClassroomAssignment(coursework: courseworkItem, courseName: course.name)
            DispatchQueue.main.async {
                if assignments[courseworkItem.id] == nil {
                    assignments[courseworkItem.id] = newAssignment
                    Task {
                        await newAssignment.syncStatusWithGoogleClassroom()
                    }
                }
            }
            return newAssignment
        }
    }

    // Filter coursework by status
    private var filteredCoursework: [ClassroomCoursework] {
        guard !statusFilters.isEmpty else { return [] }

        return coursework.filter { courseworkItem in
            if let assignment = assignments[courseworkItem.id] {
                return statusFilters.contains(assignment.status)
            } else {
                // Create assignment asynchronously, show initially (will filter after sync)
                let _ = getOrCreateAssignment(for: courseworkItem)
                return true
            }
        }
    }

    // Computed properties to avoid state modification warnings
    private var emptyStateIcon: String {
        statusFilters.isEmpty ? "line.3.horizontal.decrease.circle.slash" : "checkmark.circle"
    }

    private var emptyStateText: String {
        statusFilters.isEmpty ? "Select a status filter" : "No matching assignments"
    }

    var body: some View {
        let filtered = filteredCoursework

        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { _ in onToggle() }
            )
        ) {
            // Coursework items
            if filtered.isEmpty {
                HStack {
                    Image(systemName: emptyStateIcon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(emptyStateText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            } else {
                ForEach(filtered.sorted(by: { (a, b) -> Bool in
                    // Sort by due date (most urgent first)
                    guard let dateA = a.dueDate?.date, let dateB = b.dueDate?.date else {
                        return false
                    }
                    return dateA < dateB
                })) { courseworkItem in
                    let assignment = getOrCreateAssignment(for: courseworkItem)
                    let hasAttachments = courseworkItem.materials?.isEmpty == false

                    if hasAttachments {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedAssignments.contains(courseworkItem.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedAssignments.insert(courseworkItem.id)
                                    } else {
                                        expandedAssignments.remove(courseworkItem.id)
                                    }
                                }
                            )
                        ) {
                            // Show attachments
                            if let materials = courseworkItem.materials {
                                ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                                    AttachmentRowCompact(
                                        material: material,
                                        onSelect: { onSelectAttachment(material) }
                                    )
                                    .padding(.leading, 20)
                                }
                            }
                        } label: {
                            Button(action: {
                                onSelectAssignment(assignment)
                            }) {
                                AssignmentRowCompactView(assignmentWrapper: assignment)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: {
                            onSelectAssignment(assignment)
                        }) {
                            AssignmentRowCompactView(assignmentWrapper: assignment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            CourseRowCompact(course: course)
        }
    }
}

// MARK: - Compact Course Row

struct CourseRowCompact: View {
    let course: ClassroomCourse

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.headline)

                if let section = course.section, !section.isEmpty {
                    Text(section)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Compact Assignment Row

struct AssignmentRowCompactView: View {
    @ObservedObject var assignmentWrapper: ClassroomAssignment

    var body: some View {
        HStack(spacing: 8) {
            // Subject indicator - only show if analyzed
            if let subject = assignmentWrapper.subject {
                Image(systemName: subjectIcon(for: subject))
                    .foregroundColor(.blue)
                    .font(.body)
            }

            // Status icon
            Image(systemName: assignmentWrapper.status.iconName)
                .foregroundColor(Color(assignmentWrapper.status.color))
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(assignmentWrapper.coursework.title)
                        .font(.subheadline)
                        .lineLimit(1)

                    // Attachment count badge
                    if let materials = assignmentWrapper.coursework.materials, !materials.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(materials.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if let dueDate = assignmentWrapper.coursework.dueDate?.date {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Due \(dueDate, formatter: compactDateFormatter)")
                            .font(.caption2)
                    }
                    .foregroundColor(dueDate < Date() ? .red : .secondary)
                }
            }

            Spacer()

            // Sync indicator
            if assignmentWrapper.isSyncingStatus {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 20)
        .onAppear {
            Task {
                await assignmentWrapper.syncStatusWithGoogleClassroom()
            }
        }
    }

    /// Returns an SF Symbol icon name for the given subject
    private func subjectIcon(for subject: String) -> String {
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
            return "graduationcap"
        }
    }
}

// MARK: - Compact Attachment Row

struct AttachmentRowCompact: View {
    let material: Material
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            if let driveFile = material.driveFile?.driveFile {
                AppLogger.ui.info("User tapped attachment in tree: \(driveFile.title)")
            }
            onSelect()
        }) {
            HStack(spacing: 8) {
                // Icon based on attachment type
                if let driveFile = material.driveFile?.driveFile {
                    let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()
                    if fileExtension == "pdf" {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.red)
                    } else if fileExtension == "odt" {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.purple)
                    } else if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.gray)
                    }

                    Text(driveFile.title)
                        .font(.caption)
                        .lineLimit(1)
                } else if let link = material.link {
                    Image(systemName: "link")
                        .foregroundColor(.orange)
                    Text(link.title ?? link.url)
                        .font(.caption)
                        .lineLimit(1)
                } else if let video = material.youtubeVideo {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundColor(.red)
                    Text(video.title)
                        .font(.caption)
                        .lineLimit(1)
                } else if let form = material.form {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundColor(.green)
                    Text(form.title)
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Screen Attachment Viewer

struct AttachmentViewerFullScreen: View {
    let material: Material
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Main content
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading attachment...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
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
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    attachmentContent
                }
            }

            // Close button overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 36, height: 36)
                            )
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
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
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            // Full screen image viewer
            if let fileData = fileData, let image = UIImage(data: fileData) {
                FullScreenImageViewer(image: image, title: driveFile.title)
            } else {
                Text("Loading image...")
                    .foregroundColor(.white)
            }
        } else if fileExtension == "pdf" {
            // Full screen PDF viewer
            if let fileData = fileData {
                FullScreenPDFViewer(pdfData: fileData, title: driveFile.title)
            } else {
                Text("Loading PDF...")
                    .foregroundColor(.white)
            }
        } else {
            // Generic file - show info on dark background
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                Text(driveFile.title)
                    .font(.headline)
                    .foregroundColor(.white)
                if let url = URL(string: driveFile.alternateLink) {
                    SwiftUI.Link("Open in Drive", destination: url)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func linkViewer(_ link: ClassroomLink) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            if let title = link.title {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
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
        }
        .padding()
    }

    @ViewBuilder
    private func videoViewer(_ video: YouTubeVideo) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text(video.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: video.alternateLink) {
                SwiftUI.Link("Watch on YouTube", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func formViewer(_ form: Form) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text(form.title)
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: form.formUrl) {
                SwiftUI.Link("Open Form", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func loadAttachment() {
        // Only load Drive files (images and PDFs)
        guard let driveFile = material.driveFile?.driveFile else {
            // Links, videos, and forms don't need loading
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let data = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)
                await MainActor.run {
                    fileData = data
                    isLoading = false
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

// MARK: - Full Screen Image Viewer

struct FullScreenImageViewer: View {
    let image: UIImage
    let title: String
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Full Screen PDF Viewer

struct FullScreenPDFViewer: View {
    let pdfData: Data
    let title: String

    var body: some View {
        if let pdfDocument = PDFDocument(data: pdfData) {
            PDFKitViewFullScreen(document: pdfDocument)
                .edgesIgnoringSafeArea(.all)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Failed to load PDF")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding()
        }
    }
}

struct PDFKitViewFullScreen: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .black
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - Formatters

private let compactDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()

#Preview {
    NavigationView {
        GoogleClassroomView(
            selectedCourse: .constant(nil),
            selectedAssignment: .constant(nil),
            selectedAttachment: .constant(nil)
        )
    }
}
