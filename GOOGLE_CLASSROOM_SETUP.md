# Google Classroom Integration Setup Guide

This guide will walk you through setting up Google Classroom integration for the Homework app.

## Overview

The integration allows your son to:
- Sign in to Google Classroom
- View his courses
- See assignments with due dates
- Have authentication persist between app sessions

## Step 1: Add Google Sign-In SDK

1. Open your Xcode project
2. Go to **File → Add Package Dependencies...**
3. In the search bar, paste: `https://github.com/google/GoogleSignIn-iOS`
4. Select version **7.0.0** or later
5. Click **Add Package**
6. When prompted, select **GoogleSignIn** and **GoogleSignInSwift** libraries
7. Click **Add Package** again

## Step 2: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Name it something like "Homework App"

## Step 3: Enable Google Classroom API

1. In Google Cloud Console, go to **APIs & Services → Library**
2. Search for "Google Classroom API"
3. Click on it and press **Enable**

## Step 4: Create OAuth 2.0 Credentials

### A. Create iOS OAuth Client ID

1. Go to **APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Select **iOS** as the application type
4. Name it "Homework App - iOS"
5. For **Bundle ID**, enter your app's bundle identifier (e.g., `com.yourname.Homework`)
   - You can find this in Xcode under your project settings → General → Bundle Identifier
6. Click **Create**
7. **Important**: Copy the **Client ID** that appears (looks like: `123456789-abcdefg.apps.googleusercontent.com`)

## Step 5: Configure the App

### A. Update GoogleAuthService.swift

1. Open `Homework/Services/GoogleAuthService.swift`
2. Find this line:
   ```swift
   private let clientID = "YOUR_CLIENT_ID_HERE"
   ```
3. Replace `YOUR_CLIENT_ID_HERE` with your actual Client ID from Step 4

### B. Update Info.plist

1. Open `Homework/Info.plist` (right-click → Open As → Source Code)
2. Add the following before the closing `</dict>` tag:

```xml
<!-- Google Sign-In URL Scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR-CLIENT-ID</string>
        </array>
    </dict>
</array>
```

**Important**: Replace `YOUR-CLIENT-ID` with the **reversed** version of your Client ID.

For example, if your Client ID is:
```
123456789-abcdefg.apps.googleusercontent.com
```

Then use:
```
com.googleusercontent.apps.123456789-abcdefg
```

## Step 6: Test the Integration

1. Build and run the app
2. Navigate to the "Google Classroom" section in the sidebar
3. Tap "Sign in with Google"
4. Complete the Google Sign-In flow
5. You should see a list of courses

### Troubleshooting

**Problem**: "Sign-in failed" error
- Verify your Client ID is correct in `GoogleAuthService.swift`
- Verify the URL scheme is correct in `Info.plist`
- Make sure Google Classroom API is enabled in Google Cloud Console

**Problem**: "Not authenticated with Google" error
- Sign out and sign in again
- Check that the Client ID matches the one in Google Cloud Console

**Problem**: No courses showing up
- Verify your son has courses in Google Classroom
- Check that you've enabled the correct API scopes
- Look at Xcode console logs for detailed error messages

## Step 7: Verify Persistent Authentication

1. Sign in to Google Classroom
2. Close the app completely (swipe up from app switcher)
3. Reopen the app
4. After Face ID/Touch ID, navigate to Google Classroom section
5. You should still be signed in (no need to sign in again)

## Security Notes

- The app uses the official Google Sign-In SDK which handles token storage securely in the iOS Keychain
- Access tokens are automatically refreshed when they expire
- The app only requests read-only access to courses and coursework
- No Google credentials are stored by the app directly

## Privacy & Permissions

The app requests these Google permissions:
- `classroom.courses.readonly` - View Google Classroom courses
- `classroom.coursework.me.readonly` - View coursework and grades

These are read-only permissions and cannot modify or delete anything in Google Classroom.

## Next Steps

Once setup is complete, you can:
- View all active courses
- See assignments with due dates
- Get notified of overdue assignments
- Integrate classroom assignments with the homework analysis system (future feature)

## Support

If you encounter issues:
1. Check Xcode console for error messages
2. Verify all steps were completed correctly
3. Try signing out and signing in again
4. Verify your Google account has access to Google Classroom
