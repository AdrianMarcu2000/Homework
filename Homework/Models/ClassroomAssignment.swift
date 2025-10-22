//
//  ClassroomAssignment.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation
import UIKit
import Combine
import OSLog

/// Assignment status from Google Classroom
enum AssignmentStatus: String, Codable, CaseIterable {
    case new = "NEW"
    case created = "CREATED"
    case turnedIn = "TURNED_IN"
    case returned = "RETURNED"
    case reclaimedByStudent = "RECLAIMED_BY_STUDENT"

    var displayName: String {
        switch self {
        case .new: return "Not Started"
        case .created: return "In Progress"
        case .turnedIn: return "Turned In"
        case .returned: return "Returned"
        case .reclaimedByStudent: return "Reclaimed"
        }
    }

    var iconName: String {
        switch self {
        case .new: return "doc.badge.plus"
        case .created: return "pencil.circle.fill"
        case .turnedIn: return "checkmark.circle.fill"
        case .returned: return "arrow.uturn.backward.circle.fill"
        case .reclaimedByStudent: return "arrow.counterclockwise.circle.fill"
        }
    }

    var color: UIColor {
        switch self {
        case .new: return .systemBlue
        case .created: return .systemOrange
        case .turnedIn: return .systemGreen
        case .returned: return .systemPurple
        case .reclaimedByStudent: return .systemYellow
        }
    }

    init?(googleState: String) {
        self.init(rawValue: googleState)
    }
}

/// A wrapper around ClassroomCoursework that can be analyzed like homework
class ClassroomAssignment: ObservableObject, Identifiable, AnalyzableHomework, Hashable {
    let coursework: ClassroomCoursework
    let courseName: String

    @Published var imageData: Data?
    @Published var extractedText: String?
    @Published var analysisJSON: String?
    @Published var exerciseAnswers: [String: Data]?
    @Published var isDownloadingImage: Bool = false
    @Published var downloadError: String?
    @Published var status: AssignmentStatus = .new
    @Published var isSyncingStatus: Bool = false
    @Published var subject: String?

    var id: String {
        coursework.id
    }

    var title: String {
        coursework.title
    }

    var date: Date? {
        // Parse creation time from ISO 8601 string
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: coursework.creationTime)
    }

    /// Returns the first image material from the coursework, if any
    var firstImageMaterial: DriveFile? {
        guard let materials = coursework.materials else { return nil }

        for material in materials {
            if let driveFile = material.driveFile?.driveFile {
                // Check if it's an image by looking at the title extension
                let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif"]
                let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()

                if imageExtensions.contains(fileExtension) {
                    return driveFile
                }
            }
        }

        return nil
    }

    /// Returns the first PDF material from the coursework, if any
    var firstPDFMaterial: DriveFile? {
        guard let materials = coursework.materials else { return nil }

        for material in materials {
            if let driveFile = material.driveFile?.driveFile {
                let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()
                if fileExtension == "pdf" {
                    return driveFile
                }
            }
        }

        return nil
    }

    /// Returns all image, PDF, and ODT materials from the coursework
    var allImageAndPDFMaterials: [DriveFile] {
        guard let materials = coursework.materials else { return [] }

        var files: [DriveFile] = []
        let acceptedExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "pdf", "odt"]

        for material in materials {
            if let driveFile = material.driveFile?.driveFile {
                let fileExtension = (driveFile.title as NSString).pathExtension.lowercased()
                if acceptedExtensions.contains(fileExtension) {
                    files.append(driveFile)
                }
            }
        }

        return files
    }

    init(coursework: ClassroomCoursework, courseName: String) {
        self.coursework = coursework
        self.courseName = courseName

        // Try to load cached analysis from UserDefaults
        loadFromCache()
    }

    // MARK: - File Download

    /// Downloads the image from Google Drive if available
    func downloadImage() async throws {
        guard let driveFile = firstImageMaterial else {
            throw ClassroomAssignmentError.noImageAttached
        }

        await MainActor.run {
            isDownloadingImage = true
            downloadError = nil
        }

        do {
            let imageData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)

            await MainActor.run {
                self.imageData = imageData
                self.isDownloadingImage = false
                // Don't save to cache - images should always be fetched fresh from Google Drive
            }
        } catch {
            await MainActor.run {
                self.isDownloadingImage = false
                self.downloadError = error.localizedDescription
            }
            throw error
        }
    }

    /// Downloads a PDF file from Google Drive and extracts selected pages as images
    ///
    /// - Parameters:
    ///   - driveFile: The PDF file to download
    ///   - pageIndices: Selected page indices (0-based). If more than 3 pages, only first 3 will be used.
    /// - Returns: Array of images extracted from the PDF
    func downloadAndProcessPDF(driveFile: DriveFile, pageIndices: [Int]) async throws -> [UIImage] {
        await MainActor.run {
            isDownloadingImage = true
            downloadError = nil
        }

        do {
            AppLogger.google.info("Downloading PDF: \(driveFile.title)")
            let pdfData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFile.id)

            // Limit to 3 pages max
            let limitedIndices = Array(pageIndices.prefix(3))
            AppLogger.image.info("Extracting \(limitedIndices.count) pages from PDF")

            // Extract selected pages as images
            let images = PDFProcessingService.shared.extractPages(from: pdfData, pageIndices: limitedIndices, scale: 2.0)

            guard !images.isEmpty else {
                throw ClassroomAssignmentError.pdfProcessingFailed("No pages could be extracted from PDF")
            }

            await MainActor.run {
                // Combine multiple images into one for display and analysis
                if images.count == 1 {
                    self.imageData = images[0].jpegData(compressionQuality: 0.8)
                } else if let combinedImage = PDFProcessingService.shared.combineImages(images, spacing: 20) {
                    self.imageData = combinedImage.jpegData(compressionQuality: 0.8)
                } else {
                    // Fallback to first image
                    self.imageData = images[0].jpegData(compressionQuality: 0.8)
                }
                self.isDownloadingImage = false
            }

            AppLogger.image.info("Successfully processed \(images.count) PDF pages")
            return images
        } catch {
            await MainActor.run {
                self.isDownloadingImage = false
                self.downloadError = error.localizedDescription
            }
            throw error
        }
    }

    /// Downloads all attachments (images and PDFs) for analysis
    func downloadAllAttachments() async throws -> [UIImage] {
        let files = allImageAndPDFMaterials

        guard !files.isEmpty else {
            throw ClassroomAssignmentError.noAttachments
        }

        await MainActor.run {
            isDownloadingImage = true
            downloadError = nil
        }

        var allImages: [UIImage] = []

        do {
            for file in files {
                let fileExtension = (file.title as NSString).pathExtension.lowercased()

                if fileExtension == "pdf" {
                    AppLogger.google.info("Downloading PDF: \(file.title)")
                    let pdfData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: file.id)

                    // Get page count
                    if let pageCount = PDFProcessingService.shared.getPageCount(from: pdfData) {
                        AppLogger.image.info("PDF has \(pageCount) pages")

                        // If PDF has more than 3 pages, we'll need user selection
                        // For now, auto-select first 3 pages
                        let pageIndices = Array(0..<min(pageCount, 3))
                        let pdfImages = PDFProcessingService.shared.extractPages(from: pdfData, pageIndices: pageIndices, scale: 2.0)
                        allImages.append(contentsOf: pdfImages)
                    }
                } else if fileExtension == "odt" {
                    AppLogger.google.info("Downloading ODT: \(file.title)")
                    let odtData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: file.id)

                    // Extract text and images from ODT
                    if let content = ODTProcessingService.shared.extractContent(from: odtData) {
                        AppLogger.image.info("Extracted \(content.images.count) images from ODT")
                        allImages.append(contentsOf: content.images)
                    }
                } else {
                    // Regular image file
                    AppLogger.google.info("Downloading image: \(file.title)")
                    let imageData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: file.id)
                    if let image = UIImage(data: imageData) {
                        allImages.append(image)
                    }
                }
            }

            await MainActor.run {
                // Store combined image for display
                if allImages.count == 1 {
                    self.imageData = allImages[0].jpegData(compressionQuality: 0.8)
                } else if let combinedImage = PDFProcessingService.shared.combineImages(allImages, spacing: 20) {
                    self.imageData = combinedImage.jpegData(compressionQuality: 0.8)
                } else if let firstImage = allImages.first {
                    self.imageData = firstImage.jpegData(compressionQuality: 0.8)
                }
                self.isDownloadingImage = false
            }

            AppLogger.google.info("Successfully downloaded and processed \(allImages.count) attachment(s)")
            return allImages
        } catch {
            await MainActor.run {
                self.isDownloadingImage = false
                self.downloadError = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Caching

    private var cacheKey: String {
        "classroom_assignment_\(coursework.id)"
    }

    private func loadFromCache() {
        let defaults = UserDefaults.standard

        // ONLY load user's draft answers and AI analysis results
        // Images and OCR text should be fetched fresh from Google Classroom/Drive
        // Assignment metadata (status, due dates, etc.) should always come from Google Classroom

        if let json = defaults.string(forKey: "\(cacheKey)_analysis") {
            self.analysisJSON = json
        }

        if let answersData = defaults.data(forKey: "\(cacheKey)_answers"),
           let answers = try? JSONDecoder().decode([String: Data].self, from: answersData) {
            self.exerciseAnswers = answers
        }

        if let subject = defaults.string(forKey: "\(cacheKey)_subject") {
            self.subject = subject
        }
    }

    func saveToCache() {
        let defaults = UserDefaults.standard

        // ONLY save user's draft answers and AI analysis results
        // Images and OCR text should be fetched fresh from Google Classroom/Drive
        // Assignment metadata (status, due dates, etc.) should always come from Google Classroom

        if let json = analysisJSON {
            defaults.set(json, forKey: "\(cacheKey)_analysis")
        }

        if let answers = exerciseAnswers,
           let answersData = try? JSONEncoder().encode(answers) {
            defaults.set(answersData, forKey: "\(cacheKey)_answers")
        }

        if let subject = subject {
            defaults.set(subject, forKey: "\(cacheKey)_subject")
        }

        // Force synchronize to ensure write completes immediately
        defaults.synchronize()
    }

    // MARK: - Status Syncing

    /// Syncs assignment status from Google Classroom API
    func syncStatusWithGoogleClassroom() async {
        await MainActor.run {
            self.isSyncingStatus = true
        }

        do {
            if let submission = try await GoogleClassroomService.shared.fetchSubmissionStatus(
                courseId: coursework.courseId,
                courseWorkId: coursework.id
            ) {
                if let googleStatus = AssignmentStatus(googleState: submission.state) {
                    await MainActor.run {
                        if self.status != googleStatus {
                            AppLogger.google.info("Syncing status from Google Classroom: \(submission.state) -> \(googleStatus.displayName)")
                            self.status = googleStatus
                        }
                        self.isSyncingStatus = false
                    }
                } else {
                    await MainActor.run {
                        self.isSyncingStatus = false
                    }
                }
            } else {
                // No submission found, default to .new
                await MainActor.run {
                    if self.status != .new {
                        self.status = .new
                    }
                    self.isSyncingStatus = false
                }
            }
        } catch {
            AppLogger.google.error("Failed to sync status from Google Classroom", error: error)
            await MainActor.run {
                self.isSyncingStatus = false
            }
        }
    }

    // MARK: - Hashable

    static func == (lhs: ClassroomAssignment, rhs: ClassroomAssignment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Errors specific to classroom assignments
enum ClassroomAssignmentError: LocalizedError {
    case noImageAttached
    case noAttachments
    case pdfProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImageAttached:
            return "This assignment has no image attachments"
        case .noAttachments:
            return "This assignment has no file attachments"
        case .pdfProcessingFailed(let message):
            return "Failed to process PDF: \(message)"
        }
    }
}
