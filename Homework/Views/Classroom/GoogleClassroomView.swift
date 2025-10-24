//
//  GoogleClassroomView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import GoogleSignIn
import OSLog
import PDFKit

// Type alias to disambiguate from SwiftUI.Link
typealias ClassroomLink = Link

/// View for Google Classroom integration with tree structure navigation
struct GoogleClassroomView: View {
    @StateObject private var authService = GoogleAuthService.shared
    @State private var courses: [ClassroomCourse] = []
    @State private var courseworkByID: [String: [ClassroomCoursework]] = [:]
    @State private var assignments: [String: ClassroomAssignment] = [:]
    @State private var expandedCourses: Set<String> = []
    @State private var expandedAssignments: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var statusFilters: Set<AssignmentStatus> = Set(AssignmentStatus.allCases)

    @Binding var selectedCourse: ClassroomCourse?
    @Binding var selectedAssignment: ClassroomAssignment?
    @Binding var selectedAttachment: Material?

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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if authService.isSignedIn && !courses.isEmpty {
                    Menu {
                        Button(action: {
                            if statusFilters.isEmpty {
                                statusFilters = Set(AssignmentStatus.allCases)
                            } else {
                                statusFilters.removeAll()
                            }
                        }) {
                            HStack {
                                Image(systemName: statusFilters.isEmpty ? "checkmark.square" : "square")
                                Text(statusFilters.isEmpty ? "Select All" : "Clear All")
                            }
                        }

                        Divider()

                        ForEach(AssignmentStatus.allCases, id: \.self) { status in
                            Button(action: {
                                if statusFilters.contains(status) {
                                    statusFilters.remove(status)
                                } else {
                                    statusFilters.insert(status)
                                }
                                AppLogger.ui.info("User toggled filter: \(status.displayName)")
                            }) {
                                HStack {
                                    Image(systemName: statusFilters.contains(status) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(Color(status.color))
                                    Image(systemName: status.iconName)
                                        .foregroundColor(Color(status.color))
                                    Text(status.displayName)
                                        .foregroundColor(Color(status.color))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            if !statusFilters.isEmpty {
                                Text("\(statusFilters.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .help("Filter by status")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
                            CourseSectionView(
                                course: course,
                                isExpanded: expandedCourses.contains(course.id),
                                coursework: courseworkByID[course.id] ?? [],
                                statusFilters: statusFilters,
                                assignments: $assignments,
                                expandedAssignments: $expandedAssignments,
                                onToggle: {
                                    toggleCourse(course)
                                },
                                onSelectAssignment: { assignment in
                                    selectedAttachment = nil // Clear attachment when selecting assignment
                                    selectedAssignment = assignment
                                },
                                onSelectAttachment: { attachment in
                                    selectedAssignment = nil // Clear assignment when selecting attachment
                                    selectedAttachment = attachment
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
        AppLogger.google.info("User initiated Google sign-in")
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            AppLogger.google.error("Could not find root view controller", error: NSError(domain: "GoogleClassroom", code: -1))
            return
        }

        authService.signIn(presentingViewController: rootViewController)
    }

    private func signOut() {
        AppLogger.google.info("User signed out of Google Classroom")
        authService.signOut()
        courses = []
        courseworkByID = [:]
        expandedCourses = []
    }
    private func loadCourses() {
        AppLogger.google.info("Loading Google Classroom courses")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                courses = try await GoogleClassroomService.shared.fetchCourses()
                isLoading = false
                AppLogger.google.info("Loaded \(courses.count) courses successfully")
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                AppLogger.google.error("Failed to load courses", error: error)
            }
        }
    }

    private func toggleCourse(_ course: ClassroomCourse) {
        if expandedCourses.contains(course.id) {
            expandedCourses.remove(course.id)
            AppLogger.ui.info("User collapsed course: \(course.name)")
        } else {
            expandedCourses.insert(course.id)
            AppLogger.ui.info("User expanded course: \(course.name)")
            // Load coursework if not already loaded
            if courseworkByID[course.id] == nil {
                loadCoursework(for: course)
            }
        }
    }

    private func loadCoursework(for course: ClassroomCourse) {
        AppLogger.google.info("Loading coursework for course: \(course.name)")
        Task {
            do {
                let coursework = try await GoogleClassroomService.shared.fetchCoursework(for: course.id)
                await MainActor.run {
                    courseworkByID[course.id] = coursework
                    AppLogger.google.info("Loaded \(coursework.count) assignments for \(course.name)")
                }
            } catch {
                AppLogger.google.error("Failed to load coursework for \(course.name)", error: error)
            }
        }
    }
}
