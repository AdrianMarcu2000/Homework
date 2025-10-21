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

    init(coursework: ClassroomCoursework, courseName: String) {
        self.coursework = coursework
        self.courseName = courseName

        // Try to load cached analysis from UserDefaults
        loadFromCache()
    }

    // MARK: - Image Download

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

    var errorDescription: String? {
        switch self {
        case .noImageAttached:
            return "This assignment has no image attachments"
        }
    }
}
