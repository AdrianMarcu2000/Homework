# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Homework** is an iOS/iPadOS application that helps students manage and analyze homework using OCR and AI. The app allows users to capture homework pages (via camera or photo library), extracts text using Vision framework OCR, and uses Apple's Foundation Models (Apple Intelligence) to intelligently segment content into lessons and exercises.

**Target Platform:** iPad (iOS 18.1+)
**Bundle ID:** BlueFern.Homework
**Development Team:** T8ZCG5A8A4

## Dependencies

This project uses Swift Package Manager with the following packages:
- **Firebase iOS SDK** (v12.4.0+) - FirebaseAppCheck, FirebaseCore for cloud function authentication
- **GoogleSignIn-iOS** (v9.0.0+) - GoogleSignIn, GoogleSignInSwift for Google Classroom OAuth

## Building and Running

This is a standard Xcode project:

```bash
# Open the project in Xcode
open Homework.xcodeproj

# Build from command line
xcodebuild -project Homework.xcodeproj -scheme Homework -configuration Debug build

# Clean build
xcodebuild -project Homework.xcodeproj -scheme Homework clean
```

**Important:** This app requires:
- iOS 18.1+ (for on-device Apple Intelligence features, iOS 26.0+ deployment target)
- Physical iPad device or iPad simulator with iOS 18.1+
- Camera permissions (NSCameraUsageDescription) for capturing homework images
- Face ID permissions (NSFaceIDUsageDescription) for biometric authentication
- iCloud entitlements (using NSPersistentCloudKitContainer)
- Google OAuth client ID configured in Info.plist (CFBundleURLTypes)
- Firebase project configured for App Check (production builds only)

## Architecture

### Core Workflows

#### Manual Homework Capture (Original Flow)

1. **Image Capture** → User selects image via camera/photo library (`ImagePicker`, `HomeworkCaptureViewModel`)
2. **OCR Processing** → Vision framework extracts text and position data (`OCRService`)
3. **Image Segmentation** → Detects gaps in OCR blocks to split page into logical sections (`ImageSegmentationService`)
4. **AI Analysis** → User chooses analysis method:
   - **On-Device** (default): Apple Intelligence via `AIAnalysisService` (requires iOS 18.1+)
   - **Cloud-Based** (optional): Firebase Functions via `CloudAnalysisService` with Google Gemini
5. **Data Persistence** → Results saved to Core Data with CloudKit sync (`PersistenceController`)
6. **Display** → Structured view of lessons, exercises with cropped images (`HomeworkListView`, `LessonsAndExercisesView`)

#### Google Classroom Integration (New Flow)

1. **Authentication** → OAuth sign-in via `GoogleAuthService` with persistent sessions
2. **Course Discovery** → Fetch courses from Google Classroom API (`GoogleClassroomService`)
3. **Assignment Fetching** → Browse coursework and materials (PDF/images) per course
4. **File Download** → Download homework images from Google Drive
5. **AI Analysis** → Same analysis pipeline as manual capture (on-device or cloud)
6. **In-App Completion** → Students answer exercises using inline/canvas/text inputs

### Key Services

**OCRService** (`OCRService.swift`)
- Singleton service using Vision framework's `VNRecognizeTextRequest`
- Extracts text with Y-coordinate position data (normalized 0.0-1.0)
- Returns `OCRResult` containing both full text and positioned `OCRBlock` arrays
- Used by: `HomeworkCaptureViewModel.performOCR(on:)`

**ImageSegmentationService** (`Services/ImageSegmentationService.swift`)
- Singleton service that segments homework images into logical sections
- Analyzes gaps between OCR blocks (default threshold: 5% of image height)
- Returns array of `ImageSegment` with cropped images and associated OCR blocks
- Key methods:
  - `segmentImage(image:ocrBlocks:gapThreshold:)` - Detects gaps and creates segments
  - `mergeSmallSegments(_:minSegmentHeight:fullImage:)` - Merges fragments to avoid over-segmentation
- Each segment contains: `startY`, `endY`, `croppedImage`, `ocrBlocks`

**AIAnalysisService** (`Services/AIAnalysisService.swift`)
- Singleton service using Apple's FoundationModels framework (on-device)
- **Segment-based analysis** - Analyzes each section individually with full-page OCR context
- Requires iOS 18.1+ for Apple Intelligence availability
- Key methods:
  - `analyzeHomeworkWithSegments(image:ocrBlocks:completion:)` - **Primary method** using segment-based text analysis
  - `analyzeHomework(image:ocrBlocks:completion:)` - Single-pass full-page analysis (fallback)
  - `generateSimilarExercises(basedOn:count:completion:)` - Creates practice exercises
  - `generateHints(for:completion:)` - Generates 3 progressive hints per exercise
- Uses `SystemLanguageModel` with full-page OCR context provided to each segment
- Each segment analyzed individually but with awareness of full page structure via OCR text
- Returns structured JSON parsed into `AnalysisResult`, `SimilarExercise`, and `Hint` types
- **Important:** AI responses must avoid LaTeX notation; the service includes `extractJSON()` helper to clean responses

**CloudAnalysisService** (`Services/CloudAnalysisService.swift`)
- Alternative analysis service using Firebase Functions with Google Gemini (cloud-based)
- Enabled via `AppSettings.shared.useCloudAnalysis` toggle
- Firebase endpoint configuration:
  - **DEBUG**: `http://127.0.0.1:5001/homework-66038/us-central1` (bypasses App Check)
  - **RELEASE**: `https://us-central1-homework-66038.cloudfunctions.net` (requires App Check token)
- Key method: `analyzeHomework(image:ocrBlocks:completion:)` - Sends JPEG + OCR to cloud
- Returns `CloudAnalysisResult` converted to `AIAnalysisService.AnalysisResult` format
- Advantages: More powerful model, better OCR correction, works on older iOS versions

**AnswerVerificationService** (`Services/AnswerVerificationService.swift`)
- Verifies student answers against exercises using cloud AI
- Supports three input types: `canvas` (PencilKit drawings), `text`, `inline`
- Firebase endpoint: `/verifyAnswer` with App Check protection
- Returns `VerificationResult`: correctness confidence ("high"/"medium"/"low"), feedback, suggestions
- Converts PencilKit drawings to JPEG for multimodal analysis
- Key method: `verifyAnswer(exercise:answerType:answerText:canvasDrawing:completion:)`

**GoogleClassroomService** (`Services/GoogleClassroomService.swift`)
- Singleton service for Google Classroom REST API v1
- Requires OAuth access token from `GoogleAuthService`
- Key methods:
  - `fetchCourses()` - Returns array of `ClassroomCourse` (filters by `isActive`)
  - `fetchCoursework(for:)` - Returns `ClassroomCoursework` (assignments) for a course
  - `downloadDriveFile(fileId:)` - Downloads attached files via Google Drive API
- Data models include: `ClassroomCourse`, `ClassroomCoursework`, `Material`, `DriveFile`, `DueDate`
- Required OAuth scopes: `classroom.courses.readonly`, `classroom.coursework.me.readonly`, `drive.readonly`

**GoogleAuthService** (`Services/GoogleAuthService.swift`)
- Manages Google OAuth 2.0 authentication with persistent sessions
- Uses GoogleSignIn SDK with client ID: `190405920069-macgciftprs07shg98ctcrnnpc4s2i16.apps.googleusercontent.com`
- Key methods:
  - `restorePreviousSignIn()` - Auto-restore user session on app launch
  - `signIn(presentingViewController:)` - OAuth flow with scope approval
  - `getAccessToken()` - Returns valid token (auto-refreshes if expired)
  - `signOut()` - Clears session
- Published properties: `@Published var isSignedIn`, `currentUser: GIDGoogleUser?`

**BiometricAuthService** (`Services/BiometricAuthService.swift`)
- Singleton service for Face ID/Touch ID/Passcode authentication
- Uses LocalAuthentication framework (`LAContext`)
- Key methods:
  - `biometricType()` - Returns `.faceID`, `.touchID`, or `.none`
  - `authenticate(completion:)` - Triggers biometric prompt with fallback to passcode
  - `lock()` - Resets authentication state
- Published properties: `@Published var isAuthenticated`

### Data Model

**Core Data Entity: Item** (defined in `Homework.xcdatamodeld`)
- `timestamp: Date?` - When homework was captured
- `extractedText: String?` - Full OCR text
- `imageData: Binary?` - JPEG compressed image (external storage enabled)
- `analysisJSON: String?` - JSON-encoded `AIAnalysisService.AnalysisResult`
- `exerciseAnswersData: Binary?` - JSON dictionary mapping exercise keys to drawing canvas data

**Item Extensions** (`Models/Item+Extensions.swift`)
- `analysis: String?` - Computed property for type-safe access to `analysisJSON`
- `analysisResult: AIAnalysisService.AnalysisResult?` - Decodes JSON to structured analysis
- `exerciseAnswers: [String: Data]?` - Typed access to answer data per exercise (canvas drawings, text answers, inline answers)

**AnalyzableHomework Protocol** (`Models/AnalyzableHomework.swift`)
- Protocol abstracting homework items that can be analyzed and answered
- Adopted by both `Item` (Core Data) and `ClassroomAssignment` (transient)
- Required properties: `imageData`, `analysisResult`, `exerciseAnswers`
- Enables shared UI components (`ExerciseCardContent`) across manual and Classroom homework

**ClassroomAssignment** (`Models/ClassroomAssignment.swift`)
- Transient model for Google Classroom assignments (not persisted to Core Data)
- Conforms to `AnalyzableHomework` protocol
- Properties: `id`, `courseId`, `coursework` (metadata), `imageData`, `analysisResult`, `exerciseAnswers`
- Managed by `AssignmentDetailView` for in-memory analysis and answering

**AppSettings** (`Models/AppSettings.swift`)
- Singleton settings manager using `@AppStorage`
- `@AppStorage("useCloudAnalysis") var useCloudAnalysis: Bool = false` - Toggle between on-device and cloud AI

**Persistence** (`Persistence.swift`)
- Uses `NSPersistentCloudKitContainer` with iCloud sync
- Singleton: `PersistenceController.shared`
- Preview instance: `PersistenceController.preview` (in-memory for SwiftUI previews)

### View Architecture

**ContentView** (`ContentView.swift`)
- Root coordinator view using NavigationView with master-detail pattern
- Manages `HomeworkCaptureViewModel` lifecycle
- Presents sheets for image picker and OCR results
- Delegates to `HomeworkListView` (master) and `HomeworkDetailView` (detail)

**HomeworkListView** (`Views/HomeworkListView.swift`)
- Uses `@FetchRequest` to display all homework items
- Toolbar with camera/library buttons (styled with `GlassmorphicButtonStyle`)
- Master list with `HomeworkRowView` cells showing thumbnails and text previews
- Detail pane shows `HomeworkDetailView` with 3 tabs: Image, Lessons, Exercises

**LessonsAndExercisesView** (`Views/LessonsAndExercisesView.swift`)
- Renders analyzed lessons and exercises from `AnalysisResult`
- `LessonCard` - Displays lesson topic and content with position coordinates
- `ExerciseCard` - Interactive exercise cards with:
  - Hints button → opens `HintsView` sheet
  - Practice button → opens `SimilarExercisesView` sheet
  - Embedded `DrawingCanvasView` for student answers

**DrawingCanvasView** (`Views/DrawingCanvasView.swift`)
- PencilKit canvas for handwritten/drawn exercise answers
- Persists drawing data to `exerciseAnswers` via key: `"\(exerciseNumber)_\(startY)_canvas"`
- Supports undo/redo, eraser, color picker
- Can convert drawing to image for answer verification

**TextAnswerView** (`Views/TextAnswerView.swift`)
- Multi-line text input for essay/short-answer exercises
- Markdown-style editor with formatting toolbar
- Persists text to `exerciseAnswers` via key: `"\(exerciseNumber)_\(startY)_text"`

**InlineAnswerView** (`Views/InlineAnswerView.swift`)
- Compact single-line text field for fill-in-the-blank exercises
- Appears when exercise `inputType` is `"inline"`
- Persists text to `exerciseAnswers` via key: `"\(exerciseNumber)_\(startY)_inline"`
- Auto-saves on text change

**SimilarExercisesView** (`Views/SimilarExercisesView.swift`)
- Generates and displays AI-created practice exercises with varying difficulty

**HintsView** (`Views/HintsView.swift`)
- Progressive hint system (3 levels) using AI analysis
- Reveals hints incrementally to guide students without giving answers

**VerificationResultView** (`Views/VerificationResultView.swift`)
- Displays AI-verified answer results with confidence levels
- Shows feedback and suggestions for improvement
- Color-coded: green (correct), yellow (partial), red (incorrect)

**GoogleClassroomView** (`Views/GoogleClassroomView.swift`)
- Master view for Google Classroom integration
- Sign-in prompt → Course list with selection
- Displays logged-in email and sign-out button
- Uses `GoogleAuthService` and `GoogleClassroomService`

**CourseDetailView** (`Views/CourseDetailView.swift`)
- Shows assignments (coursework) for selected course
- Displays due dates, points, assignment descriptions
- Lists attached materials (PDFs, images, links)
- Navigates to `AssignmentDetailView` for solving

**AssignmentDetailView** (`Views/AssignmentDetailView.swift`)
- Transient assignment viewer (uses `ClassroomAssignment`, not Core Data)
- Downloads image from Drive → OCR → AI Analysis → Answer exercises
- Manages in-memory state for homework downloaded from Classroom
- Three tabs: Image, Lessons, Exercises (similar to `HomeworkDetailView`)

**AuthenticationView** (`Views/AuthenticationView.swift`)
- Lock screen with biometric authentication
- Displays Face ID/Touch ID/Passcode prompt
- Gates access to app content via `BiometricAuthService`

**SettingsView** (`Views/SettingsView.swift`)
- App settings panel with toggle for `useCloudAnalysis`
- Shows current authentication method (Face ID/Touch ID/Passcode)
- May include other preferences in future

### ViewModel Pattern

**HomeworkCaptureViewModel** (`ViewModels/HomeworkCaptureViewModel.swift`)
- Manages state for image capture → OCR → AI analysis pipeline
- Published properties: `selectedImage`, `showImagePicker`, `extractedText`, `isProcessingOCR`, `showTextSheet`
- Orchestrates async operations: `performOCR(on:)` → `analyzeHomeworkContent(image:ocrBlocks:)`
- Saves complete homework items to Core Data via `saveHomework(context:)`

## AI Integration Notes

### Apple Intelligence Requirements
- Check availability: `AIAnalysisService.shared.isModelAvailable`
- Uses `LanguageModelSession` from FoundationModels
- All AI operations run async via Swift concurrency (`Task { try await session.respond(to: prompt) }`)

### Prompt Engineering
- The AI analysis prompt is in `AIAnalysisService.analyzeHomework()`
- **Critical requirement:** Responses must be valid JSON only (no LaTeX, no extra text)
- OCR blocks provided with Y-coordinates help AI determine content boundaries
- Exercise types: `mathematical`, `multiple_choice`, `short_answer`, `essay`, `fill_in_blanks`, `true_or_false`, `matching`, `calculation`, `proof`, `diagram`, `other`

### JSON Parsing Challenges
- `extractJSON(from:)` method handles AI responses that may include wrapper text
- Attempts to fix LaTeX notation that breaks JSON (e.g., `\(` → `\\(`)
- Extensive error logging for debugging JSON parsing issues (see `print()` statements in service methods)

## Common Patterns

### Core Data Operations
```swift
// Always use the environment's managed object context
@Environment(\.managedObjectContext) private var viewContext

// Create new item
let newItem = Item(context: viewContext)
newItem.timestamp = Date()
try viewContext.save()

// Access analysis result
if let analysis = item.analysisResult {
    // Use analysis.lessons and analysis.exercises
}
```

### AI Service Calls
```swift
AIAnalysisService.shared.analyzeHomework(
    image: image,
    ocrBlocks: blocks
) { result in
    DispatchQueue.main.async {
        switch result {
        case .success(let analysis):
            // Handle analysis
        case .failure(let error):
            // Handle error
        }
    }
}
```

### Image Handling
```swift
// Store image
if let imageData = uiImage.jpegData(compressionQuality: 0.8) {
    item.imageData = imageData
}

// Load image
if let imageData = item.imageData,
   let uiImage = UIImage(data: imageData) {
    // Use image
}
```

## Project Structure

```
Homework/
├── HomeworkApp.swift              # App entry point
├── ContentView.swift              # Root coordinator view
├── Persistence.swift              # Core Data stack
├── Homework.xcdatamodeld/         # Core Data model (Item entity)
├── Models/
│   ├── Item+Extensions.swift      # Core Data extensions
│   ├── AnalyzableHomework.swift   # Protocol for homework items
│   ├── ClassroomAssignment.swift  # Transient Classroom model
│   └── AppSettings.swift          # App preferences (cloud toggle)
├── ViewModels/
│   └── HomeworkCaptureViewModel.swift
├── Views/
│   ├── HomeworkListView.swift     # Manual homework master-detail
│   ├── LessonsAndExercisesView.swift
│   ├── DrawingCanvasView.swift    # PencilKit canvas
│   ├── TextAnswerView.swift       # Multi-line text input
│   ├── InlineAnswerView.swift     # Single-line fill-in-blank
│   ├── MathNotebookCanvasView.swift # Math-focused canvas variant
│   ├── VerificationResultView.swift # Answer verification results
│   ├── SimilarExercisesView.swift
│   ├── HintsView.swift
│   ├── OCRResultView.swift
│   ├── GoogleClassroomView.swift  # Classroom courses list
│   ├── CourseDetailView.swift     # Assignments per course
│   ├── AssignmentDetailView.swift # Solve Classroom homework
│   ├── AuthenticationView.swift   # Biometric lock screen
│   ├── SettingsView.swift         # App preferences
│   └── Shared/
│       └── ExerciseCardContent.swift # Reusable exercise UI
├── Services/
│   ├── OCRService.swift           # Vision OCR wrapper
│   ├── AIAnalysisService.swift    # On-device Apple Intelligence
│   ├── CloudAnalysisService.swift # Firebase + Gemini cloud AI
│   ├── AnswerVerificationService.swift # Cloud answer checking
│   ├── ImageSegmentationService.swift  # OCR-based segmentation
│   ├── GoogleAuthService.swift    # OAuth sign-in with Google
│   ├── GoogleClassroomService.swift # Classroom REST API
│   ├── BiometricAuthService.swift # Face ID/Touch ID auth
│   └── AppCheckConfiguration.swift # Firebase App Check setup
├── ImagePicker.swift              # UIImagePickerController bridge
├── Extensions/
│   └── UIImage+Crop.swift         # Image cropping utilities
├── Styles/
│   └── GlassmorphicButtonStyle.swift
├── Info.plist                     # Google OAuth URL scheme
├── Homework.entitlements          # iCloud + App Groups
└── GoogleService-Info.plist       # Firebase configuration (if exists)
```

## Segment-Based Analysis Architecture

The app uses a hybrid approach combining OCR-based segmentation with focused AI text analysis:

### Phase 1: Segmentation
1. OCR extracts text blocks with Y-coordinates (Vision framework, bottom-left origin)
2. `ImageSegmentationService` detects gaps between blocks (default: 5% threshold)
3. Image is split into logical segments based on detected gaps
4. Small segments are merged to avoid over-fragmentation (min height: 3%)
5. Each segment gets its own cropped image + associated OCR blocks

### Phase 2: Text-Based Segment Analysis
1. For each segment, AI receives:
   - **Full page OCR text** (for context and relationships)
   - **Segment OCR text** (for focused analysis)
   - **Segment position** (Y-coordinates and segment number)
2. AI classifies segment as: `lesson`, `exercise`, or `neither`
3. Understands context from full page OCR (e.g., exercise numbering sequence)
4. Focused analysis on just the segment's text content

### Phase 3: Result Combination
1. All segment results aggregated into single `AnalysisResult`
2. Lessons and exercises maintain their Y-coordinates for image cropping
3. Results saved to Core Data as JSON
4. Cropped images displayed in UI using stored coordinates

### Advantages
✅ Context preservation (full page OCR visible to AI)
✅ Better accuracy per section (focused analysis)
✅ Logical segmentation based on page structure
✅ Visual display (cropped images shown in exercise/lesson cards)

### Coordinate System Notes
- Vision OCR: Y=0 is **bottom**, Y=1 is **top** (bottom-left origin)
- Image cropping: Flips Y coordinates to match UIKit (top-left origin)
- All stored coordinates use Vision's bottom-left convention for consistency

## Common Integration Patterns

### Using Cloud Analysis vs On-Device
```swift
// Check user preference
if AppSettings.shared.useCloudAnalysis {
    CloudAnalysisService.shared.analyzeHomework(image: image, ocrBlocks: blocks) { result in
        // Handle cloud result
    }
} else {
    AIAnalysisService.shared.analyzeHomeworkWithSegments(image: image, ocrBlocks: blocks) { result in
        // Handle on-device result
    }
}
```

### Google Classroom OAuth Flow
```swift
// 1. Sign in (usually from GoogleClassroomView)
GoogleAuthService.shared.signIn(presentingViewController: viewController)

// 2. Fetch courses
let courses = try await GoogleClassroomService.shared.fetchCourses()

// 3. Fetch assignments for a course
let assignments = try await GoogleClassroomService.shared.fetchCoursework(for: courseId)

// 4. Download attached file
let imageData = try await GoogleClassroomService.shared.downloadDriveFile(fileId: driveFileId)
```

### Answer Verification Flow
```swift
// Verify a canvas drawing answer
AnswerVerificationService.shared.verifyAnswer(
    exercise: exercise,
    answerType: "canvas",
    canvasDrawing: pkDrawing
) { result in
    switch result {
    case .success(let verification):
        // Show VerificationResultView with feedback
    case .failure(let error):
        // Handle error
    }
}
```

### Exercise Answer Storage
- **Canvas answers**: Key format `"\(exerciseNumber)_\(startY)_canvas"`, stored as `PKDrawing.dataRepresentation()`
- **Text answers**: Key format `"\(exerciseNumber)_\(startY)_text"`, stored as UTF-8 `Data`
- **Inline answers**: Key format `"\(exerciseNumber)_\(startY)_inline"`, stored as UTF-8 `Data`
- All answers stored in `Item.exerciseAnswersData` or `ClassroomAssignment.exerciseAnswers` as `[String: Data]`

## Logging Standards

This project uses Swift's OSLog framework via a centralized `AppLogger` utility for structured logging.

### Logging Principles

**CRITICAL: All new code MUST follow these logging principles:**

1. **Use AppLogger, NEVER use `print()`**
   - All logging goes through `AppLogger` in `Utilities/AppLogger.swift`
   - `print()` statements are NOT allowed in production code
   - Exception: Temporary debugging during development (must be removed before commit)

2. **Log Levels**
   - **`.info()`** - Use for:
     - User interactions (button taps, inputs, navigation, selections)
     - Third-party SDK/API interactions (Firebase, Google, Vision framework)
     - Important state changes visible to users
     - Successful completion of user-initiated operations
   - **`.error()`** - Use for:
     - All caught exceptions and errors
     - Failed operations with user impact
     - Network failures, API errors, service errors
     - **MUST include error details**: Always pass the `Error` object when available

3. **Never Log**
   - Internal UI rendering details
   - Component lifecycle events (onAppear, onDisappear)
   - Computed property evaluations
   - State variable updates unless directly user-triggered
   - Verbose debug information about internal implementation

### AppLogger Categories

The `AppLogger` provides 10 specialized categories:

```swift
AppLogger.ui          // User interface interactions
AppLogger.ocr         // Vision framework OCR operations
AppLogger.ai          // On-device Apple Intelligence
AppLogger.cloud       // Firebase Cloud Functions
AppLogger.google      // Google APIs (Classroom, Drive, Auth)
AppLogger.persistence // Core Data and CloudKit operations
AppLogger.auth        // Biometric authentication, security
AppLogger.subscription // StoreKit, subscription management
AppLogger.image       // Image processing, segmentation
AppLogger.lifecycle   // App launch, initialization
```

### Usage Examples

**User Interactions:**
```swift
// Button taps
AppLogger.ui.info("User selected camera for homework capture")
AppLogger.ui.info("User tapped verify answer button")

// User inputs
AppLogger.ui.info("User entered text answer for exercise \(exerciseNumber)")
AppLogger.ui.info("User signed out from Google Classroom")

// Navigation
AppLogger.ui.info("User navigated to course: \(courseName)")
```

**Third-Party SDK/API Calls:**
```swift
// API requests
AppLogger.google.info("Fetching courses from Google Classroom")
AppLogger.cloud.info("Sending verification request to cloud function")

// API responses
AppLogger.ocr.info("OCR completed successfully: \(blocks.count) blocks, \(fullText.count) characters")
AppLogger.ai.info("Analysis complete with \(exercises.count) exercises identified")

// SDK operations
AppLogger.auth.info("Initiating biometric authentication")
AppLogger.subscription.info("Checking subscription status")
```

**Error Logging:**
```swift
// With Error object (preferred)
AppLogger.ocr.error("OCR processing failed", error: error)
AppLogger.google.error("Failed to fetch courses", error: error)
AppLogger.persistence.error("Core Data save failed", error: error)

// Without Error object (when no Error is available)
AppLogger.cloud.error("Server returned error (403): Access denied")
AppLogger.ai.error("Invalid JSON response from AI model")
```

**Warning Logging:**
```swift
AppLogger.persistence.warning("Attempting to save without required field")
AppLogger.google.warning("Access token expired, refreshing...")
```

### Log Format

All logs are automatically formatted with:
- **Prefix:** `BlueFern.Homework`
- **Icon:** Visual indicator based on log level
  - ℹ️ Info
  - ❌ Error
  - ⚠️ Warning
  - 🔍 Debug (rarely used)
- **Category:** Logged via OSLog subsystem/category for filtering

Example log output:
```
ℹ️ BlueFern.Homework | User selected camera for homework capture
❌ BlueFern.Homework | OCR processing failed: The operation couldn't be completed
🌐 BlueFern.Homework | [GET] https://classroom.googleapis.com/v1/courses
✅ BlueFern.Homework | [200] https://classroom.googleapis.com/v1/courses
```

### Importing and Using

Every file that uses logging must:

1. Import OSLog:
```swift
import OSLog
```

2. Use appropriate category:
```swift
// In a view handling user interactions
AppLogger.ui.info("User action description")

// In a service calling APIs
AppLogger.google.info("API operation description")

// In error handlers
AppLogger.persistence.error("Operation failed", error: error)
```

### Best Practices

1. **Be specific but concise** - Describe what happened, not how
   - ✅ `"User verified answer for exercise 3"`
   - ❌ `"Tapped button in ExerciseCard component"`

2. **Include relevant context** - Use interpolation for IDs, counts, states
   - ✅ `"Downloaded \(courses.count) courses from classroom"`
   - ❌ `"Downloaded courses"`

3. **Log before async operations** - Helps trace issues
   ```swift
   AppLogger.cloud.info("Sending analysis request to cloud function")
   let result = try await cloudFunction()
   ```

4. **Always log errors with details**
   ```swift
   catch {
       AppLogger.ai.error("Failed to generate hints", error: error)
       // Handle error
   }
   ```

5. **Use Console.app filtering** - Logs can be filtered by:
   - Subsystem: `BlueFern.Homework`
   - Category: `UI`, `OCR`, `AI`, `Cloud`, etc.
   - Log level: Info, Error, Warning

### Migration from print()

When replacing existing `print()` statements:

1. **Delete** if it's debug/internal logging (UI rendering, state updates)
2. **Replace with `.info()`** if it logs user actions or API calls
3. **Replace with `.error()`** if it logs errors or exceptions
4. **Add error parameter** if an Error object is available

Example migration:
```swift
// Before
print("User tapped camera button")
print("Error: \(error)")

// After
AppLogger.ui.info("User selected camera for homework capture")
AppLogger.ocr.error("OCR processing failed", error: error)
```

## Development Notes

- **Swift Concurrency:** Project uses `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **Deployment Target:** iOS 26.0 (bleeding-edge Xcode 16 beta requirement)
- **UI Design:** Custom glassmorphic button style with liquid glass materials, gradient toolbars, tab-based detail view
- **Error Handling:** Errors should be logged via `AppLogger.[category].error()` with proper error propagation; avoid `fatalError()` except for truly unrecoverable states
- **Preview Support:** Uses `PersistenceController.preview` for in-memory Core Data in SwiftUI previews
- **Image Cropping:** `UIImage+Crop` extension handles Y-coordinate flipping and padding for visual crops
- **Position Tracking:** Y-coordinates from Vision (0.0 = bottom, 1.0 = top) used throughout for consistency
- **Firebase Configuration:**
  - Debug builds use local emulator at `http://127.0.0.1:5001` with App Check bypassed
  - Release builds use production Firebase Functions with App Check token validation
  - Requires `GoogleService-Info.plist` for Firebase SDK initialization
- **Google OAuth:**
  - Client ID must be configured in `GoogleAuthService.swift` and Info.plist URL scheme
  - Requires callback URL scheme: `com.googleusercontent.apps.{CLIENT_ID}`
  - Sessions persist across app launches via `restorePreviousSignIn()`
