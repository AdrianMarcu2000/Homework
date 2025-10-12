//
//  GoogleClassroomView.swift
//  Homework
//
//  Created by Claude on 10.10.2025.
//

import SwiftUI
import GoogleSignIn

/// View for Google Classroom integration
struct GoogleClassroomView: View {
    @StateObject private var authService = GoogleAuthService.shared
    @State private var courses: [ClassroomCourse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Binding var selectedCourse: ClassroomCourse?

    var body: some View {
        Group {
            if authService.isSignedIn {
                // Show courses list
                coursesListView
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

    // MARK: - Courses List View

    private var coursesListView: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                if isLoading {
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
                    List(selection: $selectedCourse) {
                        ForEach(courses.filter { $0.isActive }) { course in
                            CourseRow(course: course)
                                .tag(course)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCourse = course
                                }
                        }
                    }
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
}

// MARK: - Course Row

struct CourseRow: View {
    let course: ClassroomCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.name)
                .font(.headline)

            if let section = course.section, !section.isEmpty {
                Text(section)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let description = course.descriptionHeading, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationView {
        GoogleClassroomView(selectedCourse: .constant(nil))
    }
}
