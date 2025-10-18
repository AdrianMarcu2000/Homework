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

        // Add query parameters to fetch more courses and include all states
        var urlComponents = URLComponents(string: "\(baseURL)/courses")!
        urlComponents.queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
            // Don't filter by courseStates - we want all courses
        ]

        guard let url = urlComponents.url else {
            throw ClassroomError.apiError("Failed to construct URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📚 Fetching courses from Google Classroom...")
        print("🔗 Request URL: \(url.absoluteString)")
        print("🔑 Access Token (first 20 chars): \(accessToken.prefix(20))...")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the HTTP response status
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let errorJSON = String(data: data, encoding: .utf8) {
                    print("❌ Error Response: \(errorJSON)")
                }
                throw ClassroomError.apiError("HTTP \(httpResponse.statusCode): Request failed")
            }
        }

        // Log the raw response for debugging
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("📄 Raw API Response: \(rawJSON)")
        }

        // Try to decode the response
        do {
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            print("✅ Decoded response - found \(coursesResponse.courses?.count ?? 0) courses")

            // Log individual courses if any exist
            if let courses = coursesResponse.courses, !courses.isEmpty {
                for course in courses {
                    print("  📖 Course: \(course.name) (ID: \(course.id), State: \(course.courseState))")
                }
            } else {
                print("⚠️ No courses found in response - user may not be enrolled in any courses")
            }

            return coursesResponse.courses ?? []
        } catch {
            print("❌ JSON Decoding Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch for type \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found for type \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            throw error
        }
    }

    // MARK: - Coursework (Assignments)

    /// Fetch coursework for a specific course
    func fetchCoursework(for courseId: String) async throws -> [ClassroomCoursework] {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        // Add query parameters to fetch all coursework states and limit page size
        var urlComponents = URLComponents(string: "\(baseURL)/courses/\(courseId)/courseWork")!
        urlComponents.queryItems = [
            URLQueryItem(name: "pageSize", value: "100"),
            // Don't filter by courseWorkStates - we want all assignments
            // URLQueryItem(name: "courseWorkStates", value: "PUBLISHED")
        ]

        guard let url = urlComponents.url else {
            throw ClassroomError.apiError("Failed to construct URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📝 Fetching coursework for course: \(courseId)...")
        print("🔗 Request URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the HTTP response status
        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let errorJSON = String(data: data, encoding: .utf8) {
                    print("❌ Error Response: \(errorJSON)")
                }
            }
        }

        // Log the raw response for debugging
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("📄 Raw API Response: \(rawJSON)")
        }

        // Try to decode the response
        do {
            let courseworkResponse = try JSONDecoder().decode(CourseworkResponse.self, from: data)
            print("✅ Fetched \(courseworkResponse.courseWork?.count ?? 0) assignments")

            // Log individual assignments if any exist
            if let assignments = courseworkResponse.courseWork, !assignments.isEmpty {
                for assignment in assignments {
                    print("  📝 Assignment: \(assignment.title) (ID: \(assignment.id), State: \(assignment.state))")
                }
            } else {
                print("⚠️ No assignments found in response")
            }

            return courseworkResponse.courseWork ?? []
        } catch {
            print("❌ JSON Decoding Error: \(error)")
            throw error
        }
    }

    // MARK: - Drive File Download

    /// Downloads a file from Google Drive
    func downloadDriveFile(fileId: String) async throws -> Data {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        // Use the Drive API export endpoint for images
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📥 Downloading file from Google Drive: \(fileId)...")

        let (data, _) = try await URLSession.shared.data(for: request)

        print("✅ Downloaded \(data.count) bytes")

        return data
    }

    // MARK: - Assignment Submission

    /// Turns in an assignment with a PDF attachment
    ///
    /// - Parameters:
    ///   - courseId: The ID of the course
    ///   - courseWorkId: The ID of the coursework (assignment)
    ///   - pdfData: PDF file data to attach
    ///   - fileName: Name for the PDF file
    /// - Returns: The Google Drive file ID of the uploaded PDF
    func turnInAssignment(
        courseId: String,
        courseWorkId: String,
        pdfData: Data,
        fileName: String
    ) async throws -> String {
        // Force refresh the access token to ensure we have the latest scopes
        let accessToken = try await GoogleAuthService.shared.getAccessToken(forceRefresh: true)

        // Step 1: Get student submission and its current state
        let submission = try await getOrCreateSubmission(
            courseId: courseId,
            courseWorkId: courseWorkId,
            accessToken: accessToken
        )

        // Step 2: If submission is already turned in, reclaim it first
        if submission.state == "TURNED_IN" || submission.state == "RETURNED" {
            try await reclaimSubmission(
                courseId: courseId,
                courseWorkId: courseWorkId,
                submissionId: submission.id,
                accessToken: accessToken
            )
        }

        // Step 3: Upload PDF to Google Drive
        let driveFileId = try await uploadPDFToDrive(
            pdfData: pdfData,
            fileName: fileName,
            accessToken: accessToken
        )

        // Step 4: Share the file publicly
        try await shareDriveFile(driveFileId: driveFileId, accessToken: accessToken)

        // Step 5: Attach the file to the submission
        try await attachFileToSubmission(
            courseId: courseId,
            courseWorkId: courseWorkId,
            submissionId: submission.id,
            driveFileId: driveFileId,
            accessToken: accessToken
        )

        // Step 6: Turn in the submission
        try await markSubmissionAsTurnedIn(
            courseId: courseId,
            courseWorkId: courseWorkId,
            submissionId: submission.id,
            accessToken: accessToken
        )

        print("✅ Assignment turned in successfully")
        return driveFileId
    }

    // MARK: - Private Submission Helpers

    private func getOrCreateSubmission(
        courseId: String,
        courseWorkId: String,
        accessToken: String
    ) async throws -> (id: String, state: String) {
        // Get the student's submission for this assignment
        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("📝 Fetching student submission...")
        print("🔗 URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")
        }

        if let rawJSON = String(data: data, encoding: .utf8) {
            print("📄 Submission Response: \(rawJSON)")
        }

        do {
            let submissionsResponse = try JSONDecoder().decode(StudentSubmissionsResponse.self, from: data)

            guard let submissions = submissionsResponse.studentSubmissions,
                  let submission = submissions.first else {
                throw ClassroomError.apiError("No submission found for this assignment")
            }

            print("✅ Found submission - ID: \(submission.id), State: \(submission.state)")
            return (id: submission.id, state: submission.state)
        } catch {
            print("❌ Failed to decode submission response: \(error)")
            throw error
        }
    }

    private func uploadPDFToDrive(
        pdfData: Data,
        fileName: String,
        accessToken: String
    ) async throws -> String {
        // Create multipart upload request to Google Drive API
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Part 1: File metadata (JSON)
        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "application/pdf"
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)

        // Part 2: PDF file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(pdfData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("📤 Uploading PDF to Google Drive (\(pdfData.count) bytes)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("📊 HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let rawJSON = String(data: data, encoding: .utf8) {
                    print("❌ Drive Upload Error Response: \(rawJSON)")
                }

                // Try to extract error message from Google API error response
                if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorResponse["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw ClassroomError.apiError("Google Drive API error: \(message)")
                }

                throw ClassroomError.apiError("HTTP \(httpResponse.statusCode): Drive upload failed")
            }
        }

        if let rawJSON = String(data: data, encoding: .utf8) {
            print("📄 Drive Upload Response: \(rawJSON)")
        }

        do {
            let uploadResponse = try JSONDecoder().decode(DriveUploadResponse.self, from: data)
            print("✅ PDF uploaded - Drive File ID: \(uploadResponse.id)")
            return uploadResponse.id
        } catch {
            print("❌ Failed to decode Drive upload response: \(error)")
            throw error
        }
    }

    private func attachFileToSubmission(
        courseId: String,
        courseWorkId: String,
        submissionId: String,
        driveFileId: String,
        accessToken: String
    ) async throws {
        // Share the Drive file with the domain first
        try await shareDriveFile(driveFileId: driveFileId, accessToken: accessToken)

        // Modify the submission to add the attachment
        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions/\(submissionId):modifyAttachments")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "addAttachments": [
                [
                    "driveFile": [
                        "id": driveFileId
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    private func shareDriveFile(driveFileId: String, accessToken: String) async throws {
        // Share the file with anyone who has the link
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(driveFileId)/permissions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "type": "anyone",
            "role": "reader"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    private func reclaimSubmission(
        courseId: String,
        courseWorkId: String,
        submissionId: String,
        accessToken: String
    ) async throws {
        // Reclaim the submission so it can be edited again
        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions/\(submissionId):reclaim")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    private func markSubmissionAsTurnedIn(
        courseId: String,
        courseWorkId: String,
        submissionId: String,
        accessToken: String
    ) async throws {
        // Turn in the submission
        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions/\(submissionId):turnIn")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, _) = try await URLSession.shared.data(for: request)
    }
}

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

private struct StudentSubmissionsResponse: Codable {
    let studentSubmissions: [StudentSubmission]?
}

private struct StudentSubmission: Codable {
    let id: String
    let courseWorkId: String
    let userId: String
    let state: String
}

private struct DriveUploadResponse: Codable {
    let id: String
    let name: String
    let mimeType: String
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
