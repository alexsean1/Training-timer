# Production Release Checklist

## App Identity
- **App Name:** Training Timer
- **Bundle ID / Package Name:** com.trainingtimer.app
- **Version:** 1.0.0+1 (bump build number for each release)

---

## Android

### 1. Create the Release Keystore (one-time setup)

Run this **once** and keep the keystore file safe — losing it means you can never update your app:

```bash
keytool -genkey -v \
  -keystore ~/training_timer_release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias training_timer \
  -dname "CN=Training Timer, OU=Mobile, O=YourCompany, L=YourCity, S=YourState, C=US"
```

You will be prompted for a keystore password and key password. Store both securely (e.g., 1Password / Bitwarden).

**Store the keystore file in a safe location — NOT inside the git repository.**

### 2. Set Environment Variables for Signing

Before building the release App Bundle:

```bash
export KEYSTORE_PATH="$HOME/training_timer_release.jks"
export KEYSTORE_PASS="your_keystore_password"
export KEY_ALIAS="training_timer"
export KEY_PASS="your_key_password"
```

Or add these to a `local.properties` file in `mobile/android/` (already git-ignored by Flutter).

### 3. Build the Release App Bundle

```bash
cd mobile
/Users/alex/flutter/bin/flutter build appbundle --release
```

Output: `mobile/build/app/outputs/bundle/release/app-release.aab`

### 4. Google Play Store — First Upload

1. Go to https://play.google.com/console
2. Create a new app → "Training Timer"
3. Set up the store listing:
   - Short description (80 chars max)
   - Full description
   - Screenshots (phone + tablet)
   - Feature graphic (1024×500 px)
   - App icon (512×512 PNG — already generated at `assets/icon/icon.png`)
4. Upload the `.aab` file to Internal Testing track first
5. Complete content rating questionnaire
6. Set target audience (age group)
7. Privacy policy URL (required — host a simple one)

### 5. Android Permissions Review
The following permissions are declared and will be shown to users:
- Location (GPS tracking for outdoor workouts) — REQUIRED
- Bluetooth (heart rate monitor) — REQUIRED
- Notifications (workout in progress) — REQUIRED
- Foreground Service (background timer) — REQUIRED

---

## iOS

### 1. Apple Developer Account Setup

1. Enroll at https://developer.apple.com/programs/ ($99/year)
2. Create an App ID:
   - Go to Certificates, Identifiers & Profiles → Identifiers
   - Register a new App ID with bundle ID: `com.trainingtimer.app`
   - Enable capabilities: Background Modes (Audio, Location updates, Background fetch)

### 2. Xcode Signing Setup

1. Open `mobile/ios/Runner.xcworkspace` in Xcode (NOT `.xcodeproj`)
2. Select the "Runner" target → "Signing & Capabilities" tab
3. Check "Automatically manage signing"
4. Select your Apple Developer Team
5. Xcode will create the provisioning profile automatically

### 3. Build the Release IPA

```bash
cd mobile
/Users/alex/flutter/bin/flutter build ipa --release
```

Output: `mobile/build/ios/ipa/training_timer.ipa`

### 4. App Store Connect — First Upload

1. Go to https://appstoreconnect.apple.com
2. My Apps → "+" → New App → iOS
3. Bundle ID: `com.trainingtimer.app`
4. Set up store listing:
   - App name, subtitle, description
   - Keywords (comma-separated, 100 chars max)
   - Screenshots (required: 6.5" iPhone, optionally iPad)
   - App icon (already generated at `assets/icon/icon.png` — must be 1024×1024 PNG, no alpha)
5. Upload the IPA via Xcode Organizer or Transporter app
6. Submit for review (typically 24-48 hours)

### 5. iOS Privacy Review
Explain these in your App Store listing (Privacy section):
- **Location data** — used for outdoor workout distance/pace tracking
- **Bluetooth** — used to connect heart rate monitor

---

## Pre-Release Checklist

- [ ] Keystore created and backed up securely
- [ ] Environment variables set for signing
- [ ] `flutter analyze` → 0 issues
- [ ] `flutter test` → all tests pass
- [ ] Tested on physical Android device (release build)
- [ ] Tested on physical iPhone (release build)
- [ ] App icon looks correct on both platforms
- [ ] Splash screen appears and dismisses correctly
- [ ] GPS tracking tested with real location
- [ ] Heart rate monitor connects successfully
- [ ] Timer audio works with screen locked
- [ ] Background timer continues when app is backgrounded
- [ ] Privacy policy URL is live and linked in store listings
- [ ] Store listing screenshots taken on real devices
- [ ] App Store Connect app entry created
- [ ] Google Play Console app entry created

---

## Version Bumping

For each new release, increment the version in `mobile/pubspec.yaml`:
```yaml
version: 1.0.1+2   # format: major.minor.patch+buildNumber
```

The build number (`+2`) must always increase monotonically for Play Store.
The version name (`1.0.1`) is what users see.
