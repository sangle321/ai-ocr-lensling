# Implementation review — 26 October 2026

The original `implement.md` is retained as the product proposal. The app in this
repository implements the still-photo flow, with the following concrete decisions.

| Area | Decision and evidence |
| --- | --- |
| UI | Flutter, Android API 26+ on arm64, iOS 18+ on physical arm64 devices. iOS 18 avoids an OCR-only experience on older systems. |
| OCR | Pin `paddle_ocr_native` 0.1.1, which already bundles the detector, recognizer, character configuration and native SDK. Own the application adapter rather than duplicating that SDK. |
| Toolchain | The selected package requires Flutter 3.44 / Dart 3.12 or newer, Android SDK 36, Java 17 and AGP 9. The original Kotlin 2.1 / OpenCV 4.5.3 sample settings do not describe this plugin. Its Android dependency is OpenCV 4.13.0 and ONNX Runtime 1.21.1. |
| Android compatibility | The published OCR plugin registers vendored Kotlin as Java sources, which AGP 9 built-in Kotlin does not compile. `android/paddle_sources.gradle` registers that directory using the public variant API. This is a reproducible host-side fix; the package cache is not patched. |
| Model delivery | The pinned package contains approximately 29 MB of weights. `models.lock.json` and `scripts/verify_models.py` independently verify all four bundled model/configuration files. No runtime model download is needed for OCR. |
| Model tiers | The package API does not support custom model paths or switching tiers. Small is displayed as the installed model. Tiny, quantization and additional model downloads need a separate integration and parity evaluation. |
| Translation | An owned native method channel uses ML Kit on Android and Apple's view-backed TranslationSession on iOS 18+. Android batches share one translator client; Apple uses the native batch API. |
| Language packs | Explicit pair checks and download buttons. Android supports Wi-Fi-only downloads and removing the target pack. Apple owns its confirmation UI, download policy and removal. An unknown pack size is not presented as a measured size. |
| Languages | Auto detection with manual override. A conservative 13-language candidate list is filtered by the translator's actual device capabilities. Pair support is checked again before downloading or translating. These are candidates, not measured accuracy guarantees. |
| Default pair | Source auto-detect, Vietnamese target on supported devices; otherwise the first supported candidate. The launch language requirements are still unspecified. |
| Privacy | No cloud backend, API keys, analytics SDK or upload path. Store scans in app-private storage; disable Android backup/transfer and exclude iOS history from backup. Pack providers may collect their own service metrics. |
| Sharing | Android receives a single shared image through a bounded ContentResolver copy. iOS includes a native share extension that saves one photo to an App Group; open or return to Lensling to process it. |

## Reliability decisions

- Save the normalized photo and original OCR result **before** language detection
  or translation. Errors retain a useful scan in history.
- Run image decoding, orientation correction, resizing, metadata removal and
  background sampling in a Dart isolate. Reject images over 40 MB / 40 megapixels.
- Keep one OCR engine alive; serialize native operations. Group nearby horizontal
  lines, filter low confidence results and preserve original polygons.
- Sample the background, fit translated text within regions and preserve modest
  rotation. Vertical and strongly rotated regions remain in the result list.
- Changes to text or language pair clear stale translations and timing. Changing
  a confidence preference affects future scans only.
- Use atomic per-document metadata replacement. Skip corrupt records while
  retaining access to other history entries. Delete photos together with text.
- Recover an Android image-picker result after activity/process recreation.

## Gates that still require real devices and real content

Automated workflow tests cannot establish model quality or mobile performance.
Before release, collect the proposed 100–200 images per launch language, record
desktop references, and run the same images on supported phones. Measure cold
start, warm latency, memory, repeated captures and CER; do not treat the plan's
latency or accuracy targets as achieved. Complex tables, spanning headings and
multi-column layouts also need corpus-based tuning of paragraph grouping.

Run `integration_test/device_smoke_test.dart` on an arm64 Android device and a
physical iPhone. It checks actual bundled inference with a local image. Also test
camera permission denial, cancelled imports/downloads, airplane mode, short or
mixed-language text, Japanese vertical text, pack deletion, and interrupted writes.
Translation quality needs native-speaker evaluation for each launch pair.

Live camera, cloud fallback, extra model tiers and a completed golden corpus are
later-phase work. No cloud-consent toggle is shown without a working backend.
Release signing, Apple App Group provisioning and store submissions are deployment
steps outside this local implementation.

## References checked for this implementation

- [Pinned Flutter OCR package API and requirements](https://pub.dev/packages/paddle_ocr_native/versions/0.1.1)
- [Bundled model provenance](https://github.com/flespark/paddle_ocr_native/blob/main/doc/model-provenance.md)
- [Google ML Kit translation and model management](https://developers.google.com/ml-kit/language/translation/android)
- [Apple Translation sample and view-backed sessions](https://developer.apple.com/documentation/translation/translating-text-within-your-app)
