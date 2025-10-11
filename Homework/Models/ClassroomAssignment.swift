//
//  ClassroomAssignment.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation
import UIKit
import Combine

/// A wrapper around ClassroomCoursework that can be analyzed like homework
class ClassroomAssignment: ObservableObject, Identifiable, AnalyzableHomework {
    let coursework: ClassroomCoursework
    let courseName: String

    @Published var imageData: Data?
    @Published var extractedText: String?
    @Published var analysisJSON: String?
    @Published var exerciseAnswers: [String: Data]?
    @Published var isDownloadingImage: Bool = false
    @Published var downloadError: String?

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
            if let driveFile = material.driveFile {
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
                saveToCache()
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

        if let imageData = defaults.data(forKey: "\(cacheKey)_image") {
            self.imageData = imageData
        }

        if let text = defaults.string(forKey: "\(cacheKey)_text") {
            self.extractedText = text
        }

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

        if let imageData = imageData {
            defaults.set(imageData, forKey: "\(cacheKey)_image")
        }

        if let text = extractedText {
            defaults.set(text, forKey: "\(cacheKey)_text")
        }

        if let json = analysisJSON {
            defaults.set(json, forKey: "\(cacheKey)_analysis")
        }

        if let answers = exerciseAnswers,
           let answersData = try? JSONEncoder().encode(answers) {
            defaults.set(answersData, forKey: "\(cacheKey)_answers")
        }
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
