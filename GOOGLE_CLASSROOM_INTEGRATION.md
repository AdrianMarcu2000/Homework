# Google Classroom Integration Design

## Overview
Integrate Google Classroom API to automatically fetch homework assignments and sync them with the local homework analysis app.

## Architecture Components

### 1. Authentication Layer

#### GoogleAuthService
```swift
class GoogleAuthService {
    static let shared = GoogleAuthService()

    // Properties
    private var currentUser: GoogleUser?
    private var accessToken: String?
    private var refreshToken: String?

    // Methods
    func signIn() async throws -> GoogleUser
    func signOut()
    func refreshAccessToken() async throws -> String
    func isAuthenticated() -> Bool
}
```

**Implementation Options:**
- **Option A**: Use Google Sign-In SDK for iOS
  - Pros: Official, maintained, handles OAuth flow
  - Cons: Additional dependency (~3MB)

- **Option B**: Custom OAuth implementation
  - Pros: Full control, no dependencies
  - Cons: More complex, need to handle token refresh

**Recommended:** Option A (Google Sign-In SDK)

---

### 2. API Integration Layer

#### GoogleClassroomService
```swift
class GoogleClassroomService {
    static let shared = GoogleClassroomService()

    // Fetch user's courses
    func fetchCourses() async throws -> [Course]

    // Fetch coursework for a course
    func fetchCoursework(courseId: String) async throws -> [Coursework]

    // Fetch coursework details
    func fetchCourseworkDetails(courseId: String, courseworkId: String) async throws -> CourseworkDetails

    // Fetch materials/attachments
    func fetchAttachments(coursework: Coursework) async throws -> [Attachment]
}
```

**API Endpoints:**
- `GET /v1/courses` - List courses
- `GET /v1/courses/{courseId}/courseWork` - List assignments
- `GET /v1/courses/{courseId}/courseWork/{courseWorkId}` - Assignment details

---

### 3. Data Models

#### Core Models
```swift
// Course (Google Classroom class)
struct Course: Codable, Identifiable {
    let id: String
    let name: String
    let section: String?
    let descriptionHeading: String?
    let room: String?
    let ownerId: String
    let courseState: String // ACTIVE, ARCHIVED, etc.
}

// Coursework (Assignment)
struct Coursework: Codable, Identifiable {
    let id: String
    let courseId: String
    let title: String
    let description: String?
    let materials: [Material]?
    let state: String // PUBLISHED, DRAFT, DELETED
    let creationTime: Date
    let dueDate: DueDate?
    let maxPoints: Double?
}

// Material (Attachments)
struct Material: Codable {
    let driveFile: DriveFile?
    let youtubeVideo: YouTubeVideo?
    let link: Link?
    let form: Form?
}

struct DriveFile: Codable {
    let id: String
    let title: String
    let thumbnailUrl: String?
    let alternateLink: String
}
```

#### Core Data Entities
```swift
// Add new entities to existing model

@Entity ClassroomCourse
- id: String
- name: String
- section: String?
- teacherName: String?
- isActive: Bool
- lastSyncDate: Date?
- relationship: courseworkItems (one-to-many)

@Entity ClassroomCoursework
- id: String
- courseId: String
- title: String
- description: String?
- dueDate: Date?
- maxPoints: Double
- state: String
- creationTime: Date
- lastSyncDate: Date?
- relationship: course (many-to-one)
- relationship: homeworkItem (one-to-one) // Links to analyzed Item

@Entity ClassroomAttachment
- id: String
- courseworkId: String
- type: String // drive, youtube, link, form
- title: String?
- url: String
- thumbnailUrl: String?
- localFileData: Data? // Downloaded attachment
```

---

### 4. Sync Strategy

#### SyncService
```swift
class ClassroomSyncService {
    static let shared = ClassroomSyncService()

    // Full sync - fetch all courses and assignments
    func performFullSync() async throws

    // Incremental sync - fetch only new/updated assignments
    func performIncrementalSync() async throws

    // Sync specific course
    func syncCourse(_ courseId: String) async throws

    // Download attachment and analyze
    func downloadAndAnalyzeAttachment(_ attachment: ClassroomAttachment) async throws -> Item
}
```

**Sync Flow:**
1. Authenticate with Google
2. Fetch user's courses
3. For each active course:
   - Fetch coursework (assignments)
   - Check if coursework exists locally
   - If new: Download attachments → Analyze → Create Item
   - If updated: Re-download → Re-analyze
4. Store sync timestamp

**Sync Triggers:**
- Manual: Pull-to-refresh gesture
- Automatic: On app launch (if > 1 hour since last sync)
- Scheduled: Background fetch (if enabled)

---

### 5. UI Components

#### ClassroomCoursesView
```swift
struct ClassroomCoursesView: View {
    @FetchRequest var courses: FetchedResults<ClassroomCourse>
    @State private var selectedCourse: ClassroomCourse?
    @State private var isSyncing = false

    var body: some View {
        // List of courses
        // Pull-to-refresh for sync
        // Course cards with assignment count
    }
}
```

#### ClassroomCourseworkListView
```swift
struct ClassroomCourseworkListView: View {
    let course: ClassroomCourse
    @FetchRequest var coursework: FetchedResults<ClassroomCoursework>

    var body: some View {
        // List of assignments for course
        // Due date indicators
        // Status badges (submitted, graded, etc.)
        // Download button for attachments
    }
}
```

#### Updated HomeworkListView
```swift
// Add filter options:
// - All Homework
// - Google Classroom Only
// - Manual Uploads Only
// - Filter by Course
```

---

### 6. Settings Integration

#### ClassroomSettingsView
```swift
struct ClassroomSettingsView: View {
    @AppStorage("classroomSyncEnabled") var syncEnabled: Bool = false
    @AppStorage("classroomAutoSync") var autoSync: Bool = true
    @AppStorage("classroomSyncInterval") var syncInterval: Int = 3600 // seconds

    var body: some View {
        // Google account connection
        // Sync preferences
        // Course filtering
        // Auto-download preferences
    }
}
```

**Settings:**
- ✅ Enable Google Classroom integration
- ✅ Auto-sync on app launch
- ✅ Sync interval (1h, 6h, 12h, manual only)
- ✅ Auto-download attachments (WiFi only, always, never)
- ✅ Auto-analyze downloaded assignments
- ✅ Active courses filter
- ✅ Notification preferences (new assignment, due soon)

---

### 7. File Download & Analysis Pipeline

#### AttachmentDownloadService
```swift
class AttachmentDownloadService {
    static let shared = AttachmentDownloadService()

    // Download Google Drive file
    func downloadDriveFile(fileId: String) async throws -> Data

    // Export Google Docs/Sheets as PDF
    func exportAsPDF(fileId: String) async throws -> Data

    // Download and cache locally
    func downloadAndCache(attachment: ClassroomAttachment) async throws -> URL
}
```

**Download Flow:**
1. User taps "Analyze" on coursework
2. Download all attachments
3. For each attachment:
   - If image (JPG, PNG): Analyze directly
   - If PDF: Extract pages → Analyze each page
   - If Google Doc/Sheet: Export as PDF → Analyze
   - If unsupported: Show error, allow manual download
4. Create/update Item with analysis results
5. Link Item to Coursework entity

---

### 8. Security & Privacy

#### Data Storage
- Store OAuth tokens in **Keychain** (not UserDefaults)
- Use **App Groups** for sync between devices (if needed)
- Clear tokens on sign out

#### Permissions
- Request minimal scopes:
  - `classroom.courses.readonly`
  - `classroom.coursework.me.readonly`
  - `drive.readonly` (for attachments)

#### Privacy
- Allow users to:
  - Choose which courses to sync
  - Delete synced data without affecting Google Classroom
  - Disable sync at any time

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Add Google Sign-In SDK dependency
- [ ] Create GoogleAuthService
- [ ] Implement OAuth flow
- [ ] Create settings UI for account connection
- [ ] Store/retrieve tokens securely

### Phase 2: API Integration (Week 2)
- [ ] Create GoogleClassroomService
- [ ] Implement course fetching
- [ ] Implement coursework fetching
- [ ] Add Core Data entities
- [ ] Create data mapping layer

### Phase 3: Sync Logic (Week 3)
- [ ] Create ClassroomSyncService
- [ ] Implement full sync
- [ ] Implement incremental sync
- [ ] Add sync state management
- [ ] Handle errors and conflicts

### Phase 4: UI Integration (Week 4)
- [ ] Create ClassroomCoursesView
- [ ] Create ClassroomCourseworkListView
- [ ] Update HomeworkListView with filters
- [ ] Add sync status indicators
- [ ] Implement pull-to-refresh

### Phase 5: File Download & Analysis (Week 5)
- [ ] Create AttachmentDownloadService
- [ ] Implement Drive file download
- [ ] Implement PDF export for Docs/Sheets
- [ ] Integrate with existing analysis pipeline
- [ ] Handle multi-page PDFs

### Phase 6: Polish & Testing (Week 6)
- [ ] Add loading states and animations
- [ ] Implement error handling and retry logic
- [ ] Add offline support
- [ ] Test with various assignment types
- [ ] Performance optimization

---

## API Setup Requirements

### Google Cloud Console Setup
1. Create project at console.cloud.google.com
2. Enable APIs:
   - Google Classroom API
   - Google Drive API
3. Create OAuth 2.0 credentials:
   - iOS client ID
   - Bundle ID: com.yourcompany.homework
4. Add authorized domains
5. Configure OAuth consent screen
6. Add test users (for development)

### Required Scopes
```
https://www.googleapis.com/auth/classroom.courses.readonly
https://www.googleapis.com/auth/classroom.coursework.me.readonly
https://www.googleapis.com/auth/drive.readonly
```

---

## User Flows

### First Time Setup
1. User taps "Connect Google Classroom" in Settings
2. OAuth flow opens in Safari/ASWebAuthenticationSession
3. User signs in and grants permissions
4. App receives OAuth token
5. Initial sync begins
6. Courses appear in new "Classroom" tab

### Daily Usage
1. App launches → Auto-sync if enabled
2. User sees list of courses
3. Taps course → Sees assignments
4. Taps assignment → Downloads attachments
5. App analyzes PDFs/images automatically
6. Results appear in Exercises tab

### Manual Sync
1. User pulls down to refresh on Courses view
2. Sync indicator appears
3. New assignments downloaded
4. Badge shows count of new items

---

## Technical Considerations

### Rate Limiting
- Google Classroom API: 1000 requests/100 seconds
- Implement exponential backoff
- Cache aggressively
- Batch requests where possible

### Offline Support
- Cache course and coursework data
- Allow viewing cached data offline
- Queue sync for when online
- Show sync status clearly

### Performance
- Paginate course list (50 per page)
- Lazy load coursework
- Download attachments on demand
- Use background URLSession for downloads

### Error Handling
- Network errors: Retry with backoff
- Auth errors: Re-authenticate
- API errors: Log and show user-friendly message
- Parse errors: Skip item, continue sync

---

## Alternative Approaches

### Option 1: Direct Integration (Recommended)
**Pros:**
- Full control over sync logic
- Custom UI tailored to app
- Can analyze immediately after download

**Cons:**
- More development effort
- Need to handle OAuth complexity
- Maintenance burden

### Option 2: Shared Extension
**Pros:**
- Users can share from Classroom app
- Simpler implementation
- No OAuth needed

**Cons:**
- Manual process for each assignment
- No automatic sync
- User friction

### Option 3: Hybrid Approach
- Automatic sync for active courses
- Share extension for ad-hoc assignments
- Best of both worlds

**Recommended:** Hybrid Approach

---

## Success Metrics

### User Engagement
- % of users who connect Google Classroom
- Average assignments analyzed per week
- Time saved vs manual upload

### Technical
- Sync success rate > 95%
- Average sync time < 10 seconds
- Crash-free rate > 99.5%

### Business
- User retention increase
- Daily active users increase
- App Store rating improvement

---

## Future Enhancements

### Phase 2 Features
- Submit completed homework to Classroom
- View grades and feedback
- Student submissions tracking (for teachers)
- Assignment reminders/notifications
- Multi-account support
- Offline analysis queue

### Phase 3 Features
- Microsoft Teams integration
- Canvas LMS integration
- Moodle integration
- Custom LMS webhook support

---

## Dependencies

### Swift Packages
```swift
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "7.0.0"),
]
```

### CocoaPods (Alternative)
```ruby
pod 'GoogleSignIn', '~> 7.0'
```

### Minimum Requirements
- iOS 18.1+ (for Apple Intelligence)
- Swift 6.0+
- Xcode 16+

---

## Testing Strategy

### Unit Tests
- Auth token refresh logic
- API response parsing
- Sync state management
- Data model conversions

### Integration Tests
- End-to-end sync flow
- OAuth flow
- File download pipeline
- Analysis pipeline

### UI Tests
- Sign in flow
- Course selection
- Assignment download
- Error states

### Manual Testing
- Various assignment types
- Different file formats
- Network conditions (WiFi, cellular, offline)
- Large courses (100+ assignments)

---

## Documentation Needs

### Developer Documentation
- API setup guide
- Architecture overview
- Code examples
- Troubleshooting guide

### User Documentation
- Setup instructions
- FAQ
- Privacy policy update
- Tutorial video

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| API changes | High | Medium | Version API calls, monitor deprecations |
| OAuth issues | High | Low | Clear error messages, re-auth flow |
| Rate limiting | Medium | Medium | Implement caching, request batching |
| File format support | Medium | High | Graceful degradation, user guidance |
| Privacy concerns | High | Low | Clear privacy policy, minimal scopes |
| Performance issues | Medium | Medium | Lazy loading, background processing |

---

## Cost Estimate

### Development Time
- Phase 1: 40 hours
- Phase 2: 40 hours
- Phase 3: 40 hours
- Phase 4: 30 hours
- Phase 5: 30 hours
- Phase 6: 20 hours
- **Total: ~200 hours** (~5 weeks full-time)

### Ongoing Costs
- Google Cloud API: Free (< 1M requests/month)
- Storage: Minimal (cached data)
- Maintenance: ~10 hours/month

---

## Conclusion

This integration will significantly enhance the app by:
1. ✅ Automating homework ingestion
2. ✅ Reducing manual data entry
3. ✅ Providing context (course, due date, points)
4. ✅ Increasing user engagement
5. ✅ Differentiating from competitors

**Recommended Start:** Phase 1 (Authentication) - Foundation for all future features.
