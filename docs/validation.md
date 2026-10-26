# Local validation - OCR and translation app

Built with Flutter 3.47.8 / Dart 3.13.7 on Windows and JDK 17.0.20.1.

| Check | Result |
| --- | --- |
| Static analysis | Passed, no issues |
| Automated tests | Passed, 28 tests |
| Android arm64 debug APK | Built successfully, version 1.0.0+1 |
| Packaged model checksums | All four OCR model/configuration assets verified |
| Translation libraries and branding | Present and verified inside the APK |
| Native ABIs | arm64-v8a only |
| ELF native-library alignment | All load segments at least 16 KB |
| APK signing and packaging alignment | apksigner and zipalign 16 KB checks passed |
| iOS Swift / plist configuration | Syntax and plist validation passed; not Xcode type-checked |
| Android XML | Parsed successfully |
| Physical-device inference tests | Not run in this environment |

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`

Debug size: **166.2 MiB**.

SHA-256:

```text
b9200da6ceac063eceded8741ee4056c122aedea3341d0e9fae2862060c603b3
```

Tests cover the scan/translation workflow, durable OCR when language
identification or translation fails, explicit pack download and retry, uncertain
language detection, incomplete batches, editing and stale-translation invalidation,
concurrent captures, history persistence/deletion, damaged records/preferences,
image preprocessing, paragraph grouping, navigation and accessibility.

Native engines are replaced by fakes in unit/widget tests. The APK build verifies
Android compilation and packaging but does not establish inference quality or
phone latency. Run the real-engine integration test and `device-validation.md`
on physical devices before release. iOS has not been compiled, signed or run on
this Windows machine.
