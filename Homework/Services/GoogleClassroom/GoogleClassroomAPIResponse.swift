
//
//  GoogleClassroomAPIResponse.swift
//  Homework
//
//  Created by Claude on 11.10.2025.
//

import Foundation

// MARK: - API Response Wrappers

struct CoursesResponse: Codable {
    let courses: [ClassroomCourse]?
}

struct CourseworkResponse: Codable {
    let courseWork: [ClassroomCoursework]?
}

struct StudentSubmissionsResponse: Codable {
    let studentSubmissions: [StudentSubmission]?
}

struct DriveUploadResponse: Codable {
    let id: String
    let name: String
    let mimeType: String
}
