//
//  GoogleClassroomService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation

/// Service for interacting with Google Classroom API
class GoogleClassroomService {
    static let shared = GoogleClassroomService()

    private let baseURL = "https://classroom.googleapis.com/v1"

    private init() {}

    // MARK: - Courses

    /// Fetch all courses for the authenticated user
    func fetchCourses() async throws -> [ClassroomCourse] {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        let url = URL(string: "\(baseURL)/courses")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📚 Fetching courses from Google Classroom...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClassroomError.apiError("Failed to fetch courses")
        }

        let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
        print("✅ Fetched \(coursesResponse.courses?.count ?? 0) courses")

        return coursesResponse.courses ?? []
    }

    // MARK: - Coursework (Assignments)

    /// Fetch coursework for a specific course
    func fetchCoursework(for courseId: String) async throws -> [ClassroomCoursework] {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📝 Fetching coursework for course: \(courseId)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClassroomError.apiError("Failed to fetch coursework")
        }

        let courseworkResponse = try JSONDecoder().decode(CourseworkResponse.self, from: data)
        print("✅ Fetched \(courseworkResponse.courseWork?.count ?? 0) assignments")

        return courseworkResponse.courseWork ?? []
    }
}

// MARK: - Data Models

/// Google Classroom Course
struct ClassroomCourse: Codable, Identifiable {
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
    let driveFile: DriveFile?
    let youtubeVideo: YouTubeVideo?
    let link: Link?
    let form: Form?
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

// MARK: - API Response Wrappers

private struct CoursesResponse: Codable {
    let courses: [ClassroomCourse]?
}

private struct CourseworkResponse: Codable {
    let courseWork: [ClassroomCoursework]?
}

// MARK: - Errors

enum ClassroomError: LocalizedError {
    case apiError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Google Classroom API error: \(message)"
        case .notAuthenticated:
            return "Not authenticated with Google"
        }
    }
}
