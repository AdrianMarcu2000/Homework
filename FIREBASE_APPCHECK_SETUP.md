# Firebase App Check Setup Guide

This guide walks you through configuring Firebase App Check to secure your homework analysis Firebase Functions.

## Overview

**What was changed:**
- ✅ Firebase Functions now require App Check tokens (functions/src/index.ts)
- ✅ Swift app sends App Check tokens with all requests (CloudAnalysisService.swift)
- ✅ App Check configuration added (AppCheckConfiguration.swift)
- ✅ Firebase initialization updated (HomeworkApp.swift)

## Required Configurations

### Part 1: Xcode Project Setup

#### 1.1 Add Firebase SDK Dependencies

Add the following Swift Package dependencies to your Xcode project:

1. **Open Xcode** → Select your project → **Package Dependencies** tab
2. Click **"+"** to add a package
3. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
4. Add these products to your app target:
   - ✅ `FirebaseCore`
   - ✅ `FirebaseAppCheck`

**Alternative (CocoaPods):**
```ruby
pod 'Firebase/Core'
pod 'Firebase/AppCheck'
```

#### 1.2 Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **homework-66038**
3. Click **Project Settings** (gear icon)
4. Under **Your apps**, select your iOS app (or add one if needed)
5. Download **GoogleService-Info.plist**
6. **Drag it into Xcode** at the root of your Homework folder
7. ✅ Ensure "Copy items if needed" is checked
8. ✅ Ensure target membership includes "Homework"

**Expected location:** `/Homework/GoogleService-Info.plist`

#### 1.3 Verify Bundle Identifier

Make sure your iOS app bundle identifier matches the one registered in Firebase Console:

1. Xcode → Select **Homework** target → **Signing & Capabilities**
2. Check **Bundle Identifier** (e.g., `com.yourcompany.Homework`)
3. This must match the bundle ID in Firebase Console

---

### Part 2: Firebase Console Configuration

#### 2.1 Enable App Check

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **homework-66038**
3. Navigate to **App Check** (in left sidebar under "Build")
4. Click **Get started**

#### 2.2 Register iOS App with App Attest

1. In App Check, click on your iOS app
2. Choose **App Attest** as the provider
3. Click **Register**
4. ✅ App Attest will be enabled for production builds

**Note:** App Attest requires iOS 14+ and works automatically on real devices.

#### 2.3 Enable App Check for Cloud Functions

1. In App Check page, scroll to **APIs**
2. Find **Cloud Functions** in the list
3. Click the **three-dot menu** → **Enforce**
4. Confirm enforcement

**⚠️ Important:** Once enforced, ALL requests without valid App Check tokens will be rejected.

#### 2.4 Add Debug Tokens (for Development)

During development, you'll need to whitelist debug tokens:

**Step 1: Run your app in DEBUG mode**
1. Build and run in Xcode (Simulator or Device)
2. Check Xcode console for this message:
   ```
   [Firebase/AppCheck][I-FAA001001] Firebase App Check Debug Token: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
   ```
3. Copy the debug token

**Step 2: Register the token in Firebase**
1. Firebase Console → **App Check** → **Apps** tab
2. Click on your iOS app
3. Scroll to **Debug tokens** section
4. Click **Add debug token**
5. Paste the token and give it a name (e.g., "My Mac Simulator")
6. Click **Save**

**Step 3: Verify**
- Run the app again
- Try cloud analysis
- Check console logs: `DEBUG CLOUD: App Check token obtained successfully`

---

### Part 3: Deploy Firebase Functions

#### 3.1 Build TypeScript Code

```bash
cd functions
npm run build
```

This compiles `src/index.ts` → `lib/index.js`

#### 3.2 Deploy to Firebase

**For testing with emulator:**
```bash
npm run serve
```
This starts the local emulator at `http://127.0.0.1:5001`

**For production deployment:**
```bash
npm run deploy
```

Or with Firebase CLI:
```bash
firebase deploy --only functions
```

**Expected output:**
```
✔ functions[analyzeHomework(us-central1)] Successful update operation.
Function URL: https://us-central1-homework-66038.cloudfunctions.net/analyzeHomework
```

#### 3.3 Verify Deployment

Test the function is enforcing App Check:

**Without App Check token (should fail):**
```bash
curl -X POST https://us-central1-homework-66038.cloudfunctions.net/analyzeHomework \
  -H "Content-Type: application/json" \
  -d '{"imageBase64":"test","imageMimeType":"image/jpeg","ocrJsonText":"test"}'
```

**Expected response:** `401 Unauthorized: App Check token required.`

---

### Part 4: Testing the Integration

#### 4.1 Development Testing (with Debug Provider)

1. Run app in DEBUG mode
2. Register debug token (see Part 2.4)
3. Take a photo or select from library
4. Trigger cloud analysis
5. Check Xcode console logs:
   ```
   🔥 Firebase and App Check initialized
   🔐 App Check: Using Debug Provider for development
   DEBUG CLOUD: App Check token obtained successfully
   DEBUG CLOUD: Sending request to http://127.0.0.1:5001/...
   DEBUG CLOUD: Response status code: 200
   ```

#### 4.2 Production Testing (with App Attest)

1. Build in RELEASE mode:
   - Xcode → Product → Scheme → Edit Scheme
   - Run → Build Configuration → **Release**
2. Run on a **real iOS device** (App Attest requires physical device)
3. Trigger cloud analysis
4. Check console logs:
   ```
   🔐 App Check: Using App Attest Provider for production
   DEBUG CLOUD: App Check token obtained successfully
   ```

**Note:** App Attest may take a few seconds on first run as it registers the device.

---

## Troubleshooting

### Issue 1: "App Check token required" Error

**Symptoms:** Cloud analysis fails with 401 error

**Solutions:**
1. ✅ Verify `GoogleService-Info.plist` is in your Xcode project
2. ✅ Verify Firebase is initialized: Check for "🔥 Firebase and App Check initialized" in logs
3. ✅ For DEBUG builds: Register debug token in Firebase Console (Part 2.4)
4. ✅ Check Firebase Console → App Check → Apps shows your iOS app

### Issue 2: Debug Token Not Working

**Symptoms:** Still getting 401 even after registering debug token

**Solutions:**
1. ✅ Copy the EXACT token from Xcode console (starts with "Firebase App Check Debug Token:")
2. ✅ Make sure the token is registered and **not expired** in Firebase Console
3. ✅ Restart the app after registering token
4. ✅ Clear app data and reinstall

### Issue 3: "Failed to obtain App Check token"

**Symptoms:** `CloudAnalysisError.noAppCheckToken` or `appCheckFailed`

**Solutions:**
1. ✅ Verify `GoogleService-Info.plist` is correctly added to Xcode
2. ✅ Check bundle identifier matches Firebase Console
3. ✅ For production: Make sure running on iOS 14+ physical device
4. ✅ Check network connectivity

### Issue 4: Simulator vs Device Differences

**Debug Mode (Simulator):**
- Uses `AppCheckDebugProviderFactory`
- Requires registering debug tokens
- Works on simulator and device

**Release Mode (Device only):**
- Uses `AppAttestProviderFactory`
- Automatic, no tokens needed
- **Requires physical device** (won't work on simulator)

### Issue 5: Firebase Functions Return 401

**Check Firebase Console:**
1. Functions → Logs
2. Look for: "Request rejected: Missing App Check token"
3. Verify the request included `X-Firebase-AppCheck` header

**Check Swift logs:**
```
DEBUG CLOUD: App Check token included in request
```

---

## Security Best Practices

### ✅ DO:
- Always use App Check in production
- Register minimal debug tokens (only for your dev devices)
- Rotate/remove unused debug tokens regularly
- Monitor Firebase Analytics for suspicious patterns
- Keep `GoogleService-Info.plist` in `.gitignore`

### ❌ DON'T:
- Commit debug tokens to git
- Share debug tokens publicly
- Disable App Check enforcement in production
- Hardcode API keys in code

---

## Configuration Checklist

Use this checklist to verify everything is set up correctly:

### Xcode Project
- [ ] Firebase iOS SDK added via Swift Package Manager
- [ ] `FirebaseCore` and `FirebaseAppCheck` products added
- [ ] `GoogleService-Info.plist` downloaded and added to project
- [ ] `GoogleService-Info.plist` target membership includes "Homework"
- [ ] Bundle identifier matches Firebase Console
- [ ] `HomeworkApp.swift` initializes Firebase and App Check
- [ ] `AppCheckConfiguration.swift` exists in Services folder

### Firebase Console
- [ ] iOS app registered in Firebase project (homework-66038)
- [ ] App Check enabled for iOS app
- [ ] App Attest provider registered
- [ ] Cloud Functions enforcement enabled
- [ ] Debug tokens registered for development devices

### Firebase Functions
- [ ] `functions/src/index.ts` updated with App Check verification
- [ ] TypeScript code compiled: `npm run build`
- [ ] Functions deployed: `npm run deploy`
- [ ] Function logs show App Check enforcement working

### Testing
- [ ] DEBUG build works with debug token
- [ ] Cloud analysis succeeds in development
- [ ] Console shows "App Check token obtained successfully"
- [ ] Console shows "App Check token included in request"
- [ ] Firebase Functions logs show successful requests
- [ ] RELEASE build works on physical device (App Attest)

---

## Summary of Code Changes

### TypeScript (Firebase Functions)

**File:** `functions/src/index.ts`

**Changes:**
- Added App Check token verification at the start of the function
- Returns 401 if `X-Firebase-AppCheck` header is missing
- Logs security rejections

### Swift (iOS App)

**File:** `Homework/HomeworkApp.swift`

**Changes:**
- Imports `FirebaseCore` and `FirebaseAppCheck`
- Calls `FirebaseApp.configure()` in init
- Calls `AppCheckConfiguration.configure()` in init

**File:** `Homework/Services/AppCheckConfiguration.swift`

**New file** with:
- Debug provider for DEBUG builds
- App Attest provider for RELEASE builds

**File:** `Homework/Services/CloudAnalysisService.swift`

**Changes:**
- Imports `FirebaseAppCheck`
- Gets App Check token before making request
- Includes token in `X-Firebase-AppCheck` header
- Added error cases: `.appCheckFailed` and `.noAppCheckToken`

---

## Next Steps

After completing setup:

1. **Test thoroughly** with both debug and release builds
2. **Monitor Firebase Console** → Functions → Logs for any issues
3. **Set up alerts** in Firebase Console for unusual API usage
4. **Document the debug token registration process** for your team
5. **Consider adding rate limiting** to prevent abuse (future enhancement)

---

## Additional Resources

- [Firebase App Check Documentation](https://firebase.google.com/docs/app-check)
- [iOS App Check Setup Guide](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Cloud Functions Security](https://firebase.google.com/docs/functions/security)
- [App Attest Overview](https://developer.apple.com/documentation/devicecheck/establishing_your_app_s_integrity)

---

## Support

If you encounter issues not covered in this guide:

1. Check Firebase Console → Functions → Logs for error details
2. Check Xcode console for App Check debug messages
3. Verify all checklist items above are completed
4. Review the "Troubleshooting" section

**Common error patterns:**
- 401 errors → App Check token missing or invalid
- 500 errors → Firebase Function internal error (check logs)
- Network errors → Check Firebase project configuration
