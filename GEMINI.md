# Gemini Customization

This file helps customize Gemini's behavior for this project.

## Project Overview

*   **Name:** Homework App
*   **Description:** An iOS app to help students manage their homework, with features like OCR for scanning assignments, AI-powered analysis, and Google Classroom integration.
*   **Technology Stack:**
    *   **Frontend:** Swift, SwiftUI
    *   **Database:** Core Data with CloudKit sync
    *   **Backend:** Firebase Functions (TypeScript)
    *   **Authentication:** Firebase Authentication, Google Sign-In, Biometric (Face ID/Touch ID)
    *   **AI/ML:** Apple Vision Framework for OCR, Apple Intelligence for analysis.
    *   **Security:** Firebase App Check

## Building and Running

### iOS App

This is a standard Xcode project.

1.  **Open the project in Xcode:**
    ```bash
    open Homework.xcodeproj
    ```
2.  **Build and Run:**
    *   Select the "Homework" scheme.
    *   Choose a simulator or a connected device.
    *   Click the "Run" button.

**Requirements:**
*   Xcode 16+
*   iOS 18.1+

### Firebase Functions

The Firebase Functions are written in TypeScript and need to be compiled and deployed.

1.  **Install dependencies:**
    ```bash
    cd functions
    npm install
    ```
2.  **Build the functions:**
    ```bash
    npm run build
    ```
3.  **Run the emulator:**
    ```bash
    npm run serve
    ```
4.  **Deploy to Firebase:**
    ```bash
    npm run deploy
    ```

## Development Conventions

*   **Language:** Swift for the iOS app, TypeScript for Firebase Functions.
*   **Architecture:** The iOS app uses a MVVM-like architecture with services for business logic.
*   **Code Style:** Follows the [Ray Wenderlich Swift Style Guide](https://github.com/raywenderlich/swift-style-guide). Use camelCase for variables and functions, and PascalCase for types.
*   **Comments:** Use `// MARK: -` to separate logical sections of code.
*   **Core Data:** Use the `Item` entity for storing homework data. Extensions on the `Item` class provide computed properties for easier access to data.
*   **Firebase Functions:** Functions are defined in `functions/src/index.ts` and should be kept modular.

## Important Files

*   `Homework/HomeworkApp.swift`: The main entry point for the iOS app.
*   `Homework/ContentView.swift`: The main view of the app, containing the tab-based navigation.
*   `Homework/Persistence.swift`: Defines the Core Data stack.
*   `Homework.xcodeproj/project.pbxproj`: The Xcode project file, containing build settings and dependencies.
*   `functions/src/index.ts`: The source code for the Firebase Functions.
*   `firebase.json`: Configuration for Firebase services, including Functions and the emulator.
*   `CLAUDE.md`, `FIREBASE_APPCHECK_SETUP.md`, `GOOGLE_CLASSROOM_INTEGRATION.md`, `GOOGLE_CLASSROOM_SETUP.md`: Detailed documentation about different aspects of the project.
