//
//  GoogleClassroomView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import GoogleSignIn

/// View for Google Classroom integration with tree structure navigation
struct GoogleClassroomView: View {
    @StateObject private var authService = GoogleAuthService.shared
    @State private var courses: [ClassroomCourse] = []
    @State private var courseworkByID: [String: [ClassroomCoursework]] = [:]
    @State private var expandedCourses: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Binding var selectedCourse: ClassroomCourse?
    @Binding var selectedAssignment: ClassroomAssignment?

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
                                onToggle: {
                                    toggleCourse(course)
                                },
                                onSelectAssignment: { assignment in
                                    selectedAssignment = assignment
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
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Could not find root view controller")
            return
        }

        authService.signIn(presentingViewController: rootViewController)
    }

    private func signOut() {
        authService.signOut()
        courses = []
        courseworkByID = [:]
        expandedCourses = []
    }

    private func loadCourses() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                courses = try await GoogleClassroomService.shared.fetchCourses()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                print("❌ Failed to load courses: \(error)")
            }
        }
    }

    private func toggleCourse(_ course: ClassroomCourse) {
        if expandedCourses.contains(course.id) {
            expandedCourses.remove(course.id)
        } else {
            expandedCourses.insert(course.id)
            // Load coursework if not already loaded
            if courseworkByID[course.id] == nil {
                loadCoursework(for: course)
            }
        }
    }

    private func loadCoursework(for course: ClassroomCourse) {
        Task {
            do {
                let coursework = try await GoogleClassroomService.shared.fetchCoursework(for: course.id)
                await MainActor.run {
                    courseworkByID[course.id] = coursework
                }
            } catch {
                print("❌ Failed to load coursework for \(course.name): \(error)")
            }
        }
    }
}

// MARK: - Course Section (Disclosure Group)

struct CourseSection: View {
    let course: ClassroomCourse
    let isExpanded: Bool
    let coursework: [ClassroomCoursework]
    let onToggle: () -> Void
    let onSelectAssignment: (ClassroomAssignment) -> Void

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { _ in onToggle() }
            )
        ) {
            // Coursework items
            if coursework.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("No assignments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            } else {
                ForEach(coursework.sorted(by: { (a, b) -> Bool in
                    // Sort by due date (most urgent first)
                    guard let dateA = a.dueDate?.date, let dateB = b.dueDate?.date else {
                        return false
                    }
                    return dateA < dateB
                })) { assignment in
                    Button(action: {
                        onSelectAssignment(ClassroomAssignment(
                            coursework: assignment,
                            courseName: course.name
                        ))
                    }) {
                        AssignmentRowCompact(assignment: assignment)
                    }
                    .buttonStyle(.plain)
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

struct AssignmentRowCompact: View {
    let assignment: ClassroomCoursework

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.green)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.title)
                    .font(.subheadline)
                    .lineLimit(1)

                if let dueDate = assignment.dueDate?.date {
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
        }
        .padding(.vertical, 2)
        .padding(.leading, 20)
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
            selectedAssignment: .constant(nil)
        )
    }
}
