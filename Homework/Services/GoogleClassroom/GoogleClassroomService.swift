//
//  GoogleClassroomService.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import Foundation
import OSLog

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

        AppLogger.google.info("Fetching courses from Google Classroom...")
        AppLogger.google.debug("Request URL: \(url.absoluteString)")
        AppLogger.google.debug("Access Token (first 20 chars): \(accessToken.prefix(20))...")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the HTTP response status
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.debug("HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let errorJSON = String(data: data, encoding: .utf8) {
                    AppLogger.google.error("Error Response: \(errorJSON)")
                }
                throw ClassroomError.apiError("HTTP \(httpResponse.statusCode): Request failed")
            }
        }

        // Log the raw response for debugging
        if let rawJSON = String(data: data, encoding: .utf8) {
            AppLogger.google.debug("Raw API Response: \(rawJSON.prefix(500))")
        }

        // Try to decode the response
        do {
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            AppLogger.google.info("Decoded response - found \(coursesResponse.courses?.count ?? 0) courses")

            // Log individual courses if any exist
            if let courses = coursesResponse.courses, !courses.isEmpty {
                for course in courses {
                    AppLogger.google.debug("Course: \(course.name) (ID: \(course.id), State: \(course.courseState))")
                }
            } else {
                AppLogger.google.info("No courses found in response - user may not be enrolled in any courses")
            }

            return coursesResponse.courses ?? []
        } catch {
            AppLogger.google.error("JSON Decoding Error", error: error)
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    AppLogger.google.error("   Missing key: \(key.stringValue) - \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    AppLogger.google.error("   Type mismatch for type \(type) - \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    AppLogger.google.error("   Value not found for type \(type) - \(context.debugDescription)")
                case .dataCorrupted(let context):
                    AppLogger.google.error("   Data corrupted: \(context.debugDescription)")
                @unknown default:
                    AppLogger.google.error("   Unknown decoding error")
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

        AppLogger.google.info("Fetching coursework for course: \(courseId)...")
        AppLogger.google.debug("Request URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log the HTTP response status
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.debug("HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let errorJSON = String(data: data, encoding: .utf8) {
                    AppLogger.google.error("Error Response: \(errorJSON)")
                }
            }
        }

        // Log the raw response for debugging
        if let rawJSON = String(data: data, encoding: .utf8) {
            AppLogger.google.debug("Raw API Response: \(rawJSON.prefix(500))")
        }

        // Try to decode the response
        do {
            let courseworkResponse = try JSONDecoder().decode(CourseworkResponse.self, from: data)
            AppLogger.google.info("Fetched \(courseworkResponse.courseWork?.count ?? 0) assignments")

            // Log individual assignments if any exist
            if let assignments = courseworkResponse.courseWork, !assignments.isEmpty {
                for assignment in assignments {
                    AppLogger.google.debug("Assignment: \(assignment.title) (ID: \(assignment.id), State: \(assignment.state))")
                }
            } else {
                AppLogger.google.info("No assignments found in response")
            }

            return courseworkResponse.courseWork ?? []
        } catch {
            AppLogger.google.error("JSON Decoding Error", error: error)
            throw error
        }
    }

    // MARK: - Submission Status

    /// Fetch submission status for a specific assignment
    func fetchSubmissionStatus(courseId: String, courseWorkId: String) async throws -> StudentSubmission? {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        let url = URL(string: "\(baseURL)/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        AppLogger.google.info("Fetching submission status for courseWork: \(courseWorkId)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.debug("HTTP Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                if let errorJSON = String(data: data, encoding: .utf8) {
                    AppLogger.google.error("Error Response: \(errorJSON)")
                }
                throw ClassroomError.apiError("HTTP \(httpResponse.statusCode)")
            }
        }

        let submissionsResponse = try JSONDecoder().decode(StudentSubmissionsResponse.self, from: data)
        let submission = submissionsResponse.studentSubmissions?.first

        if let submission = submission {
            AppLogger.google.info("Fetched submission status: \(submission.state)")
        } else {
            AppLogger.google.info("No submission found for this assignment")
        }

        return submission
    }

    // MARK: - Drive File Download

    /// Downloads a file from Google Drive
    func downloadDriveFile(fileId: String) async throws -> Data {
        let accessToken = try await GoogleAuthService.shared.getAccessToken()

        // Use the Drive API export endpoint for images
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        AppLogger.google.info("Downloading file from Google Drive: \(fileId)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log response details
        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.info("Download HTTP Status: \(httpResponse.statusCode)")
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                AppLogger.google.info("Content-Type: \(contentType)")
            }
        }

        AppLogger.google.info("Downloaded \(data.count) bytes")

        // Log first few bytes to verify data integrity
        let previewLength = min(16, data.count)
        let preview = data.prefix(previewLength).map { String(format: "%02x", $0) }.joined(separator: " ")
        AppLogger.google.info("Data preview (first \(previewLength) bytes): \(preview)")

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

        AppLogger.google.info("Assignment turned in successfully")
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

        AppLogger.google.info("Fetching student submission...")
        AppLogger.google.debug("URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.debug("HTTP Status: \(httpResponse.statusCode)")
        }

        if let rawJSON = String(data: data, encoding: .utf8) {
            AppLogger.google.debug("Submission Response: \(rawJSON.prefix(500))")
        }

        do {
            let submissionsResponse = try JSONDecoder().decode(StudentSubmissionsResponse.self, from: data)

            guard let submissions = submissionsResponse.studentSubmissions,
                  let submission = submissions.first else {
                throw ClassroomError.apiError("No submission found for this assignment")
            }

            AppLogger.google.info("Found submission - ID: \(submission.id), State: \(submission.state)")
            return (id: submission.id, state: submission.state)
        } catch {
            AppLogger.google.error("Failed to decode submission response", error: error)
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

        AppLogger.google.info("Uploading PDF to Google Drive (\(pdfData.count) bytes)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            AppLogger.google.debug("HTTP Status: \(httpResponse.statusCode)")

            // Check for error status codes
            if httpResponse.statusCode != 200 {
                if let rawJSON = String(data: data, encoding: .utf8) {
                    AppLogger.google.error("Drive Upload Error Response: \(rawJSON)")
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
            AppLogger.google.debug("Drive Upload Response: \(rawJSON.prefix(500))")
        }

        do {
            let uploadResponse = try JSONDecoder().decode(DriveUploadResponse.self, from: data)
            AppLogger.google.info("PDF uploaded - Drive File ID: \(uploadResponse.id)")
            return uploadResponse.id
        } catch {
            AppLogger.google.error("Failed to decode Drive upload response", error: error)
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
