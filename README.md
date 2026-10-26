# Lensling

A Flutter photo OCR and translation app built from `implement.md`. Recognize text
with bundled PP-OCRv6 small models, then translate on the device with Google ML Kit
on Android or Apple Translation on iOS.

Development status: the Android debug build and automated tests pass. Physical
device accuracy/performance checks and an iOS build are still pending. See
[validation results](docs/validation.md).

## Included

- Camera, gallery, and single-image share import.
- EXIF correction, downscaling, metadata removal and confidence filtering.
- Paragraph grouping, sampled-background translation overlays, tap to toggle,
  original-text editing, copy and retry.
- Automatic source identification, manual source/target selection and swapping.
- Explicit language-pair downloads, offline availability checks and Android pack
  removal / Wi-Fi-only download preferences.
- App-private persistent history, individual deletion and delete-all.
- Error recovery that retains recognized text when translation is unavailable.
- Pinned OCR package, model hashes, automated tests and a device smoke test.

Cloud translation, live video and additional OCR model tiers are not implemented.
The [plan review](docs/plan-review.md) records assumptions and remaining device gates.

## Requirements

| Android | iOS |
| --- | --- |
| API 26+, arm64-v8a physical device | iOS 18+, arm64 physical iPhone/iPad |
| JDK 17, Android SDK 36 | macOS, Xcode 16+ and CocoaPods |

Flutter **3.44+**, Dart **3.12+**. This project was generated with Flutter 3.47.8 /
Dart 3.13.7. The OCR plugin does not support desktop, web, x86 Android emulators or
the iOS simulator. Use CocoaPods; Swift Package Manager is disabled for this app
because of the pinned OCR binary dependencies.

## Run

```sh
flutter pub get
python scripts/verify_models.py
flutter devices
flutter run -d DEVICE_ID
```

OCR works at installation time without network. On the first translation, open
**Language packs**, choose the source and target and download explicitly. Return
to the saved scan and tap **Translate**. Thereafter that pair works offline.
Source defaults to automatic detection; Vietnamese is the initial target when
available. If short or mixed text is uncertain, select the source manually.

```sh
flutter analyze
flutter test
flutter test integration_test/device_smoke_test.dart -d DEVICE_ID
flutter build apk --debug --target-platform android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. The release
configuration currently uses a debug signing key for local development; configure
your own signing before distribution.

The optional `.tools/flutter/bin/flutter.bat` SDK and `.tools/android-sdk` installed
in this workspace can be used locally. They are ignored by version control.
Set `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `PUB_CACHE` and
`GRADLE_USER_HOME` for your own machine as needed; do not commit `local.properties`.

### iOS setup

1. On a Mac, run `flutter pub get`, then `cd ios && pod install`.
2. Open **ios/Runner.xcworkspace**. Select your signing team for both **Runner** and
   **ShareExtension**, using unique bundle IDs.
3. Provision the App Group **group.app.lensling.lensling** for both targets. If you
   change it, update both entitlement files, `Runner/Info.plist` and the group
   identifier in `ShareExtension/ShareViewController.swift` together.
4. Run on a physical iOS 18+ device. Apple presents its own download confirmation.
5. Share one photo using **Read with Lensling**, tap Done, then open/return to
   Lensling. The extension uses an App Group to hand off the image without a server.

Apple controls supported language pairs, pack download policy, and pack removal.
The app filters the available language list on the device and checks the actual
pair before translation. Some candidate languages may therefore not appear on iOS.

## Layout

```text
lib/domain/          Scan models, language candidates and paragraph grouping
lib/services/        OCR adapter, translation channel, image processing and storage
lib/app_controller.dart  Scan workflow and recoverable application state
lib/ui/              Capture, overlays, history, language packs and settings
android/app/src/main/kotlin/  ML Kit and Android share bridges
ios/Runner/AppDelegate.swift Apple Translation and share-import bridges
ios/ShareExtension/   Native image share extension
test/                Workflow, image, persistence, grouping and widget tests
integration_test/    Real bundled-engine smoke test
models.lock.json     Reviewed model/configuration checksums
```

History is stored as a normalized JPEG and versioned JSON per scan. Atomic metadata
replacement protects existing records from interrupted writes. History is excluded
from OS backups. It is protected by the app sandbox; no separate application-level
encryption is implemented. No image or text upload endpoint is configured.

## Validation and release

See [device validation](docs/device-validation.md). Passing unit/widget tests does
not establish device latency, memory, accuracy parity or translation quality. A
100–200-image corpus per launch language and native-speaker translation review are
still required before making the performance claims proposed in the original plan.

Android translations display Google Translate attribution; iOS displays Apple
attribution. PaddleOCR models and the selected OCR plugin declare Apache-2.0.
Flutter's license page exposes bundled dependency notices. See
[third-party notices](THIRD_PARTY_NOTICES.md) and verify release requirements when
updating dependencies.

## Repository publication

The repository contains source, the Flutter dependency lockfile and the Android
Gradle wrapper. SDKs, build output, signing keys and local configuration are ignored.
OCR weights are supplied by the pinned package and verified against
`models.lock.json`; they are not duplicated in Git.

No license has been selected for the application's own source code. Third-party
components retain their respective licenses and attribution requirements.

See [publishing instructions](docs/publishing.md) to connect a remote and push.
