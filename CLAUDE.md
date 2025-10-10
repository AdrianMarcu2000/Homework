# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Homework** is an iOS/iPadOS application that helps students manage and analyze homework using OCR and AI. The app allows users to capture homework pages (via camera or photo library), extracts text using Vision framework OCR, and uses Apple's Foundation Models (Apple Intelligence) to intelligently segment content into lessons and exercises.

**Target Platform:** iPad (iOS 18.1+)
**Bundle ID:** BlueFern.Homework
**Development Team:** T8ZCG5A8A4

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
- iOS 18.1+ (for Apple Intelligence features)
- Physical iPad device or iPad simulator with iOS 18.1+
- Camera permissions for capturing homework images
- iCloud entitlements (using NSPersistentCloudKitContainer)

## Architecture

### Core Workflow

1. **Image Capture** → User selects image via camera/photo library (`ImagePicker`, `HomeworkCaptureViewModel`)
2. **OCR Processing** → Vision framework extracts text and position data (`OCRService`)
3. **Image Segmentation** → Detects gaps in OCR blocks to split page into logical sections (`ImageSegmentationService`)
4. **AI Analysis** → Apple Intelligence analyzes each segment with full-page context using multimodal (`AIAnalysisService`)
5. **Data Persistence** → Results saved to Core Data with CloudKit sync (`PersistenceController`)
6. **Display** → Structured view of lessons, exercises with cropped images (`HomeworkListView`, `LessonsAndExercisesView`)

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
- Singleton service using Apple's FoundationModels framework
- **NEW: Segment-based analysis** - Analyzes each section individually with full-page OCR context
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
- `exerciseAnswers: [String: Data]?` - Typed access to drawing canvas data per exercise

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
- Canvas for drawing exercise answers
- Persists drawing data to Core Data via `Item.exerciseAnswers`
- Each exercise identified by key: `"\(exerciseNumber)_\(startY)"`

**SimilarExercisesView** (`Views/SimilarExercisesView.swift`)
- Generates and displays AI-created practice exercises with varying difficulty

**HintsView** (`Views/HintsView.swift`)
- Progressive hint system (3 levels) using AI analysis
- Reveals hints incrementally to guide students without giving answers

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
│   └── Item+Extensions.swift      # Core Data extensions
├── ViewModels/
│   └── HomeworkCaptureViewModel.swift
├── Views/
│   ├── HomeworkListView.swift     # Master-detail list
│   ├── LessonsAndExercisesView.swift
│   ├── DrawingCanvasView.swift
│   ├── SimilarExercisesView.swift
│   ├── HintsView.swift
│   └── OCRResultView.swift
├── Services/
│   ├── AIAnalysisService.swift    # Apple Intelligence multimodal integration
│   └── ImageSegmentationService.swift  # OCR-based image segmentation
├── OCRService.swift               # Vision OCR wrapper
├── ImagePicker.swift              # UIImagePickerController bridge
├── Extensions/
│   └── UIImage+Crop.swift         # Image cropping utilities
├── Styles/
│   └── GlassmorphicButtonStyle.swift
├── Info.plist
└── Homework.entitlements          # iCloud + App Groups
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

## Development Notes

- **Swift Concurrency:** Project uses `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **UI Design:** Custom glassmorphic button style with liquid glass materials, gradient toolbars, tab-based detail view
- **Error Handling:** Most Core Data operations use `fatalError()` - production code would need proper error handling
- **Preview Support:** Uses `PersistenceController.preview` for in-memory Core Data in SwiftUI previews
- **Image Cropping:** `UIImage+Crop` extension handles Y-coordinate flipping and padding for visual crops
- **Position Tracking:** Y-coordinates from Vision (0.0 = bottom, 1.0 = top) used throughout for consistency
