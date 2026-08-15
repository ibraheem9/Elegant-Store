# iOS Version Support Implementation Plan

This plan outlines the steps necessary to enable and configure the iOS version of the "Abd Elhadi Store" app. The goal is to ensure all platform-specific dependencies and permissions are correctly handled for the iOS environment.

## User Review Required

> [!IMPORTANT]
> - **Apple Developer Account**: A valid Apple Developer account is required to sign the app and distribute it (or test on physical devices).
> - **macOS Environment**: Building for iOS REQUIRES a macOS machine with Xcode installed. I can prepare the configuration files here, but the final `pod install` and `flutter build ios` must be run on a Mac.
> - **Bundle Identifier**: The current bundle identifier in `Info.plist` uses variables. If you have a specific bundle ID (e.g., `com.company.abdelhadistore`), please provide it.

## Proposed Changes

### Core Configuration

#### [main.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/main.dart)
- Review for any platform-specific logic that might need adjustment for iOS (e.g., path handling, desktop-specific features).

### iOS Platform Configuration

#### [Info.plist](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/ios/Runner/Info.plist)
- Add missing usage descriptions for plugins used in `pubspec.yaml`:
    - `NSCameraUsageDescription` (for `image_picker`)
    - `NSPhotoLibraryUsageDescription` (for `image_picker`)
    - `NSFaceIDUsageDescription` (for `local_auth`)
    - `NSLocationWhenInUseUsageDescription` (already present, but verify it's sufficient)
- Ensure Arabic localization is properly declared.

#### [NEW] [Podfile](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/ios/Podfile)
- If not already generated correctly, ensure the `Podfile` specifies a minimum iOS version (suggested: 13.0 or higher) to support modern plugins.

### Dependency Management

#### [pubspec.yaml](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/pubspec.yaml)
- Verify that all dependencies have iOS support (most do, like `sqflite`, `dio`, `path_provider`).
- `window_manager` is desktop-only, so calls to it in `main.dart` must remain guarded by `Platform.isWindows`.

---

## Verification Plan

### Manual Verification (On a Mac)
1.  **Environment Check**:
    - Run `flutter doctor` to ensure iOS toolchain is set up.
2.  **Pod Installation**:
    - Navigate to `ios/` directory and run `pod install`.
3.  **Build**:
    - Run `flutter build ios --no-codesign` to verify the code compiles for iOS.
4.  **Runtime Check (Simulator/Device)**:
    - Open `ios/Runner.xcworkspace` in Xcode.
    - Run the app on an iOS Simulator or connected device.
    - Verify permissions prompts appear for Camera, Photos, and Location when accessing relevant features.
    - Verify database operations (via `sqflite`) work as expected on iOS.
    - Verify Arabic localization works correctly.

### Static Analysis
- Run `flutter analyze` to ensure no platform-neutral errors were introduced.
