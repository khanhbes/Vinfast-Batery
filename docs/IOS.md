# VinFast Battery on iOS

This document combines the iOS build, TestFlight, and free Windows sideload instructions.

## Platform configuration

- iOS 15+, portrait-only, bundle ID `com.khanhbes.vinfastbattery`.
- Firebase project: `vinfast-873db`. Register the iOS app in Firebase and keep the real
  `GoogleService-Info.plist` in `app/ios/Runner/`.
- On macOS run `flutterfire configure --platforms=ios` after registering the app.
- Enable Push Notifications, Background Modes (location, fetch, remote notifications),
  Local Network and Bonjour `_shelly._tcp` in the Apple/Firebase configuration.
- Never commit Firebase Admin JSON, APNs private keys, certificates, or provisioning files.

## Build and TestFlight

Windows cannot run Xcode. The GitHub Actions workflows build and test the unsigned iOS
application on macOS, including Flutter analyze/tests, CocoaPods and an unsigned release
build. With an Apple Developer account, configure signing secrets and enable the signing
workflow, then upload the archive to App Store Connect for internal testers.

Before a real-device release, verify Firebase Auth/Firestore, APNs, location while locked,
Shelly LAN discovery/control, Smart Charge after suspension, TFLite, PDF sharing and
notification deep links.

## Free Windows sideload

This is a personal development install, not App Store/TestFlight distribution. A free Apple
ID signing profile normally expires after seven days, APNs is unavailable, and the app must
be signed again periodically.

1. Register the iOS Firebase app and update `app/ios/Runner/GoogleService-Info.plist` and
   `app/lib/firebase_options.dart` with the iOS values.
2. In GitHub open **Actions → iOS free sideload IPA → Run workflow**.
3. Download the `VinFast-Battery-iOS-free-sideload` artifact and extract it once to obtain
   `VinFast-Battery-unsigned.ipa`.
4. Install iTunes/iCloud direct from Apple if required, install Sideloadly, connect and
   trust the iPhone, then drag the IPA into Sideloadly and sign with a dedicated Apple ID.
5. If iOS requests it, enable Developer Mode and trust the app under
   **Settings → General → VPN & Device Management**.

## Framework packaging errors

Do not reuse an old IPA when Sideloadly reports a missing framework executable. Push the
current workflow, rerun the GitHub Action, download a fresh artifact and extract it once.
The workflow verifies `CFBundleExecutable`, materializes framework symlinks for Windows and
performs an IPA round-trip check before publishing the artifact.

