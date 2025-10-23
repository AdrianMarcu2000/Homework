
//
//  GoogleClassroomDataModels.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

// MARK: - Data Models

/// Google Classroom Course
struct ClassroomCourse: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let section: String?
    let descriptionHeading: String?
    let room: String?
    let ownerId: String
    let courseState: String
    let alternateLink: String?

    var isActive: Bool {
        courseState == "ACTIVE"
    }
}

/// Google Classroom Coursework (Assignment)
struct ClassroomCoursework: Codable, Identifiable {
    let id: String
    let courseId: String
    let title: String
    let description: String?
    let materials: [Material]?
    let state: String
    let creationTime: String
    let updateTime: String?
    let dueDate: DueDate?
    let maxPoints: Double?
    let workType: String?
    let alternateLink: String?
}

/// Material attached to coursework
struct Material: Codable {
    let driveFile: DriveFileShare?
    let youtubeVideo: YouTubeVideo?
    let link: Link?
    let form: Form?
}

struct DriveFileShare: Codable {
    let driveFile: DriveFile
}

struct DriveFile: Codable {
    let id: String
    let title: String
    let alternateLink: String
    let thumbnailUrl: String?
}

struct YouTubeVideo: Codable {
    let id: String
    let title: String
    let alternateLink: String
    let thumbnailUrl: String?
}

struct Link: Codable {
    let url: String
    let title: String?
    let thumbnailUrl: String?
}

struct Form: Codable {
    let formUrl: String
    let title: String
    let thumbnailUrl: String?
}

/// Due date for coursework
struct DueDate: Codable {
    let year: Int?
    let month: Int?
    let day: Int?

    var date: Date? {
        guard let year = year, let month = month, let day = day else {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day

        return Calendar.current.date(from: components)
    }
}

struct StudentSubmission: Codable {
    let id: String
    let courseWorkId: String
    let userId: String
    let state: String
}
