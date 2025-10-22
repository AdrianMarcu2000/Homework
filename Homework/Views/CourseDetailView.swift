//
//  CourseDetailView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import OSLog
import PDFKit

/// View showing assignments (coursework) for a specific Google Classroom course
struct CourseDetailView: View {
    let course: ClassroomCourse
    @State private var coursework: [ClassroomCoursework] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAssignment: ClassroomAssignment?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading assignments...")
            } else if coursework.isEmpty {
                emptyStateView
            } else {
                assignmentsList
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(course.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let section = course.section, !section.isEmpty {
                        Text(section)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: loadCoursework) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .onAppear {
            loadCoursework()
        }
    }

    // MARK: - Assignments List

    private var assignmentsList: some View {
        NavigationStack {
            List {
                ForEach(coursework.sorted(by: { (a, b) -> Bool in
                    // Sort by due date (most urgent first)
                    guard let dateA = a.dueDate?.date, let dateB = b.dueDate?.date else {
                        return false
                    }
                    return dateA < dateB
                })) { courseworkItem in
                    NavigationLink {
                        AssignmentDetailView(
                            assignment: ClassroomAssignment(
                                coursework: courseworkItem,
                                courseName: course.name
                            )
                        )
                    } label: {
                        AssignmentRow(assignment: courseworkItem)
                    }
                }
            }
            .refreshable {
                loadCoursework()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Assignments")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("You're all caught up for this course!")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: loadCoursework) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadCoursework() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                coursework = try await GoogleClassroomService.shared.fetchCoursework(for: course.id)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                AppLogger.google.error("Failed to load coursework", error: error)
            }
        }
    }
}

// MARK: - Assignment Row

struct AssignmentRow: View {
    let assignment: ClassroomCoursework
    @State private var selectedAttachment: Material?
    @State private var showAttachmentViewer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(assignment.title)
                    .font(.headline)

                Spacer()

                if let dueDate = assignment.dueDate?.date {
                    DueDateBadge(dueDate: dueDate)
                }
            }

            if let description = assignment.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Materials section - show individual attachments
            if let materials = assignment.materials, !materials.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // Header
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Attachments:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // List each attachment
                    ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                        if let driveFile = material.driveFile?.driveFile {
                            AttachmentBadge(file: driveFile)
                                .onTapGesture {
                                    AppLogger.ui.info("User tapped to view attachment: \(driveFile.title)")
                                    selectedAttachment = material
                                    showAttachmentViewer = true
                                }
                        } else if let link = material.link {
                            LinkBadge(link: link)
                                .onTapGesture {
                                    AppLogger.ui.info("User tapped to view link: \(link.title ?? link.url)")
                                    selectedAttachment = material
                                    showAttachmentViewer = true
                                }
                        } else if let video = material.youtubeVideo {
                            VideoBadge(video: video)
                                .onTapGesture {
                                    AppLogger.ui.info("User tapped to view video: \(video.title)")
                                    selectedAttachment = material
                                    showAttachmentViewer = true
                                }
                        } else if let form = material.form {
                            FormBadge(form: form)
                                .onTapGesture {
                                    AppLogger.ui.info("User tapped to view form: \(form.title)")
                                    selectedAttachment = material
                                    showAttachmentViewer = true
                                }
                        }
                    }
                }
            }

            // Max points if available
            if let maxPoints = assignment.maxPoints {
                Text("Worth \(Int(maxPoints)) points")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showAttachmentViewer) {
            if let attachment = selectedAttachment {
                AttachmentViewerView(material: attachment)
            }
        }
    }
}

// MARK: - Due Date Badge

struct DueDateBadge: View {
    let dueDate: Date

    private var isOverdue: Bool {
        dueDate < Date()
    }

    private var isDueSoon: Bool {
        let timeInterval = dueDate.timeIntervalSinceNow
        return timeInterval > 0 && timeInterval < 86400 * 3 // 3 days
    }

    private var badgeColor: Color {
        if isOverdue {
            return .red
        } else if isDueSoon {
            return .orange
        } else {
            return .blue
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(isOverdue ? "Overdue" : "Due")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(badgeColor)

            Text(dueDate, formatter: dueDateFormatter)
                .font(.caption2)
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Formatters

private let dueDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}()

// MARK: - Attachment Badges

struct AttachmentBadge: View {
    let file: DriveFile

    private var fileExtension: String {
        (file.title as NSString).pathExtension.lowercased()
    }

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension)
    }

    private var isPDF: Bool {
        fileExtension == "pdf"
    }

    private var iconName: String {
        if isPDF {
            return "doc.fill"
        } else if isImage {
            return "photo.fill"
        } else {
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        if isPDF {
            return .red
        } else if isImage {
            return .blue
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundColor(iconColor)

            Text(file.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            if isPDF {
                Text("PDF")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            } else if isImage {
                Text("IMG")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
    }
}

struct LinkBadge: View {
    let link: Link

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.caption2)
                .foregroundColor(.orange)

            Text(link.title ?? link.url)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("LINK")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
    }
}

struct VideoBadge: View {
    let video: YouTubeVideo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.rectangle.fill")
                .font(.caption2)
                .foregroundColor(.red)

            Text(video.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("VIDEO")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
    }
}

struct FormBadge: View {
    let form: Form

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.caption2)
                .foregroundColor(.green)

            Text(form.title)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("FORM")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(6)
    }
}

// MARK: - Attachment Viewer

struct AttachmentViewerView: View {
    let material: Material
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var fileData: Data?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
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
                        Button("Dismiss") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    attachmentContent
                }
            }
            .navigationTitle(attachmentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func driveFileViewer(_ driveFile: DriveFile) -> some View {
        let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp"].contains(fileExtension) {
            // Image viewer
            if let fileData = fileData, let image = UIImage(data: fileData) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else {
                Text("Loading image...")
                    .foregroundColor(.secondary)
            }
        } else if fileExtension == "pdf" {
            // PDF viewer
            if let fileData = fileData {
                PDFViewerView(pdfData: fileData)
            } else {
                Text("Loading PDF...")
                    .foregroundColor(.secondary)
            }
        } else {
            // Generic file - show info
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text(driveFile.title)
                    .font(.headline)
                if let url = URL(string: driveFile.alternateLink) {
                    SwiftUI.Link("Open in Drive", destination: url)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func linkViewer(_ link: Link) -> some View {
        VStack(spacing: 16) {
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
                .multilineTextAlignment(.center)
                .padding()

            if let url = URL(string: form.formUrl) {
                SwiftUI.Link("Open Form", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var attachmentTitle: String {
        if let driveFile = material.driveFile?.driveFile {
            return driveFile.title
        } else if let link = material.link {
            return link.title ?? "Link"
        } else if let video = material.youtubeVideo {
            return video.title
        } else if let form = material.form {
            return form.title
        }
        return "Attachment"
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

// MARK: - PDF Viewer

struct PDFViewerView: View {
    let pdfData: Data

    var body: some View {
        if let pdfDocument = PDFDocument(data: pdfData) {
            PDFKitView(document: pdfDocument)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.badge.exclamationmark")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text("Failed to load PDF")
                    .font(.headline)
            }
            .padding()
        }
    }
}

// MARK: - PDFKit Wrapper

struct PDFKitView: UIViewRepresentable {
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

// MARK: - Preview

#Preview {
    NavigationView {
        CourseDetailView(course: ClassroomCourse(
            id: "1",
            name: "Mathematics",
            section: "Period 3",
            descriptionHeading: "Advanced Algebra",
            room: "Room 101",
            ownerId: "teacher123",
            courseState: "ACTIVE",
            alternateLink: nil
        ))
    }
}
