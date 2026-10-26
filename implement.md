# PP-OCRv6 mobile OCR and translation app: implementation plan

Oct 26, 2026 · @Sang

Run PP-OCRv6\_small on the device with ONNX Runtime, then translate the recognized text with ML Kit (Android) and Apple's Translation framework (iOS). Four phases, about 10 weeks for 1–2 engineers (my estimate).

## Decisions and assumptions

I assumed a new app for Android and iOS, offline-first, built by 1–2 engineers. Change a row and the rest of the plan shifts with it.

| Decision | Pick | Why | Alternative |
| --- | --- | --- | --- |
| Model tier | PP-OCRv6\_small (ONNX) | 7.7M parameters, 50 languages, 84.1% detection and 81.3% recognition on PaddleOCR's [in-house benchmark](https://huggingface.co/blog/PaddlePaddle/pp-ocrv6) | tiny (1.5M parameters, 73.5% recognition, language coverage not stated) for low-end phones; medium (34.5M) for server use |
| Runtime | ONNX Runtime plus OpenCV | The official [Android](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/android_deployment.html) and [iOS](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/ios_deployment.html) v6 demos both use it | Paddle-format models are also published; I found no v6 mobile path built on them |
| App stack | Flutter UI over a thin native plugin | One UI codebase; [paddle\_ocr\_native](https://pub.dev/packages/paddle_ocr_native) already follows this pattern | Pure Kotlin and Swift if you want full control of the camera pipeline |
| Translation | ML Kit on Android, Apple Translation on iOS 18+ | Free, and runs on the device once language packs are downloaded | Cloud Translation API where higher quality matters |
| Model delivery | Bundle small detection and recognition files in the app | Works on first launch with no network | Download extra tiers or languages on demand in a later phase |

If you already have a native-only team or a fine-tuned model, say so: the stack row changes first.

## Architecture

&#91;embedded content: on-device pipeline · 5 steps, 2 resource stores, 1 optional cloud exit\]

The app code owns steps 1, 3 and 5; the plugin wraps the OCR and translation engines. Recognized text, not the photo, goes to the cloud, and only if the user opts in.

## Model pipeline

Use the published ONNX files, convert them for mobile, prove them against a desktop reference, then bundle them. No training is needed to start.

1. Download the PP-OCRv6\_small detection and recognition models from the [PP-OCRv6 collection](https://huggingface.co/collections/PaddlePaddle/pp-ocrv6), which publishes ONNX variants. The recognition model ships with `inference.yml` (its character set and settings); keep it next to `inference.onnx`.
2. Build a golden test set of 100–200 images per target language. Run it on a laptop with PaddleOCR 3.7 and `engine="onnxruntime"`, and save the text and boxes as the reference.
3. iOS: convert to ORT format with the demo's `convert_onnx_to_ort.sh`; the demo loads `.ort` files first, so the `.onnx` copies need not ship. Android: the official SDK loads `inference.onnx` from assets, so treat ORT conversion as an optional start-up and size experiment.
4. Measure real file sizes and cold start. I found no published file sizes. In paddle\_ocr\_native, initialization creates two ONNX Runtime sessions and the first call is slow, so keep one instance alive for the app's lifetime and run a warm-up pass at launch.
5. Quantize the recognition model to int8 only if latency misses the target in Testing. Re-run the golden set and accept at most a 1-point accuracy drop (my threshold).
6. Pin each model file by version and SHA-256 checksum in the repo, and confirm the model license on its Hugging Face card before release.

Bundle small in the app binary. Add tiny as a low-end fallback and extra languages as downloads in Phase 4. If the golden set shows a gap on your own content (receipts, menus, screenshots), fine-tune with PaddleOCR's training tools and re-export to ONNX; I have not checked the v6 training docs yet.

## OCR integration

Start from PaddleOCR's own mobile code and hide it behind one small plugin API: `init`, `recognize(image)` and `dispose`. `recognize` returns lines with a four-point polygon, text, confidence and timing.

### Android

- Take the `ppocr-sdk` module from `deploy/ppocr-android` in the PaddleOCR repo, as a source dependency or an AAR.
- Toolchain from the [official page](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/android_deployment.html): JDK 17, Kotlin 2.1.0, minSdk 26, ONNX Runtime 1.21.1, OpenCV 4.5.3.
- Put the models in `assets/models/det/` and `assets/models/rec/`. The sample config uses detection threshold 0.3, box threshold 0.6 and 4 threads; start there.
- Ship arm64-v8a only. [paddle\_ocr\_native](https://pub.dev/packages/paddle_ocr_native) does this to keep the runtime surface small, and it also has to exclude the other ABIs' libraries from the transitive AARs.

### iOS

- Start from `deploy/ios_demo` (SwiftUI, ONNX Runtime Objective-C API, CocoaPods). It needs Xcode 16+ and targets iOS 16+, per the [iOS guide](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/ios_deployment.html).
- The demo lets you pick CPU, XNNPACK or Core ML as the preferred execution provider, and ONNX Runtime can still fall back to CPU for operators a provider lacks. Benchmark all three on your golden set instead of assuming Core ML is fastest.
- paddle\_ocr\_native does not build for the iOS simulator (its OpenCV has no simulator slice), so plan on a physical device for testing.

### What the app owns

- Image prep: apply EXIF orientation and downscale very large photos before detection.
- Orientation: handle device rotation yourself. PaddleOCR's Python quick start turns document orientation, unwarping and text-line orientation off.
- Filtering: the sample config accepts every recognition score (0.0). Set a threshold, starting at 0.5, and tune it on the golden set.
- Structure: sort lines into reading order and merge neighbors into paragraphs before translating; translating line by line gives poor results.
- Live camera: do not run OCR on every frame. Run it on a still capture first, then try 1–2 frames per second as a later option.

## Translation

Use each platform's built-in on-device translator, put language detection in front of it, and keep a cloud option for text where quality matters most.

| Platform | Engine | Works offline | Limits to plan around |
| --- | --- | --- | --- |
| Android | [ML Kit on-device Translation](https://developers.google.com/ml-kit/language/translation) | Yes, after the language pack downloads | 50+ languages; meant for casual, simple text; non-English pairs pass through English, which can hurt quality; Google's usage guidelines require attribution |
| iOS | [Apple Translation framework](<https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:).md>) | Yes, after the language downloads | `TranslationSession` needs iOS 18+ and is reached through a SwiftUI `translationTask`; it does not run in the simulator; iOS 26+ adds a session you can create without a view for installed languages |
| Both, as fallback | Cloud Translation API behind your own backend | No | Higher fidelity per Google's ML Kit guidance; needs a network, an API key on your server and a privacy notice |

Build these pieces around the engines:

- One `Translator` interface in the plugin: `isPairAvailable`, `downloadPair`, and `translate(texts, source, target)` that takes a batch. Batching is preferred over per-string loops, per a third-party write-up of the framework.
- Source language: OCR does not report it. Run on-device language identification on the recognized text, and let the user override.
- A supported-pair matrix: PP-OCRv6's 50 OCR languages intersected with each translator's list. Hide pairs that fail either side.
- Language packs as a first-class screen: size, download state, a Wi-Fi hint. On iOS the first translation for a pair triggers a system download prompt, so design for it.
- Fallback rule: if the on-device call fails or the pair is missing, offer cloud translation with the user's consent. Apple developers have reported error code 16 ("Offline models not available") even when a pair shows as installed, so test this path on real devices.

A self-hosted model (for example an Opus-MT variant run with CTranslate2) would give one engine on both platforms, at the cost of tens of MB per pair and a license check. I have not researched it; consider it only if the platform engines fail your quality tests in Phase 3.

## App features and UX

Ship a still-photo flow first. Live camera translation is a later phase because it needs OCR and translation to keep up with a moving frame.

1. **Capture:** camera photo, gallery import and share-sheet import.
2. **Result:** the photo with each translated paragraph drawn over its detected region. Tap to flip between original and translation, copy text, and edit the recognized text before translating, which is the cheapest fix for OCR mistakes.
3. **Language bar:** source (auto by default), target, a swap button, and the pack status for the pair.
4. **History:** photo, recognized text and translation stored on the device, with delete-all. No cloud sync in version 1.
5. **Settings:** model tier, language packs, and the cloud-fallback consent switch.

Overlay rules: fit the font size to each paragraph's box, rotate with the polygon's angle, and fill the box with a color sampled from the surrounding image so the original text is hidden. Show vertical or heavily rotated text as a list below the image instead of forcing it into the overlay.

Privacy default: photos and text stay on the device. Cloud translation is off until the user turns it on.

## Roadmap

&#91;embedded content: roadmap · 4 phases, 4 gates, about 10 weeks\]

Weeks are my estimates for 1–2 engineers. Phase 1 can end the project early: if the demos miss the parity gate on your languages, change the model tier or the stack before building any screens.

## Testing and benchmarks

Judge each build on accuracy against the desktop reference, speed per photo, and memory. The targets below are my proposals; reset them after the first measurements on real phones.

| Metric | How to measure | Starting target |
| --- | --- | --- |
| Accuracy parity | Golden set per language; compare phone output with the desktop ONNX Runtime run | Character error rate within 1 point of desktop |
| OCR latency | Photo with about 20 text lines; 3 warm-up runs, then the median of 10 (the official demos' benchmark defaults) | 1.5 s or less on a mid-range phone |
| Start-up | App launch to engine ready, with warm-up in the background | 1 s or less before the camera is usable |
| Peak memory | Android Studio profiler, Xcode Instruments | Set after the first run |
| Translation quality | 50 sentences per language pair, rated by a native speaker against cloud output | Understandable in 90% or more |
| Sustained use | 20 captures in a row | No thermal throttling warning |

Device matrix: one low-end Android phone (arm64, 4 GB RAM), one mid-range, one flagship, and two iPhones, one on iOS 18 or later and one older.

Tools: both official demos ship a `run_benchmark.sh`; reuse them for latency and memory instead of writing your own. Run the golden accuracy test as an on-device integration test in CI on at least one Android phone and one iPhone.

One gap to decide early: the iOS demo targets iOS 16, but Apple's programmatic translation needs iOS 18. A phone on iOS 16 or 17 can do OCR but not on-device translation (see Open questions).

## Risks

The two largest risks are the young mobile tooling around v6 and the iOS 18 requirement for translation. Both can be tested in the first two weeks.

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Early-stage mobile code: paddle\_ocr\_native is at 0.1.1, and the official demos are samples | Bugs and breaking changes land on you | Pin versions and commits, own the plugin code, and budget time for fixes in Phase 2 |
| Language gaps: the stated list is Chinese, Japanese, English and 46 Latin-script languages | Korean, Cyrillic, Arabic and similar scripts may not work | Confirm the exact list against your target languages in Phase 1; do not promise a script until the golden set passes |
| Weak translation on non-English pairs (English is the pivot) | Awkward or wrong output | Per-pair quality test in Phase 3; cloud fallback with consent |
| Apple Translation limits: iOS 18+, no simulator, error 16 reports | Split experience across iOS versions; flaky tests | Set iOS 18 as the minimum or show OCR only below it; test on physical devices |
| Slow start and high memory on low-end phones | Laggy first scan, possible crashes | Warm up in the background, offer the tiny tier, include a 4 GB phone in the matrix |
| App size growth from models, ONNX Runtime and OpenCV | Lower install rates | Measure in Phase 1; arm64 only; move extra languages to downloads |
| Accuracy loss from ORT conversion or quantization | Worse text than the desktop reference | Golden-set gate on every model change |
| Licenses: ML Kit attribution, the model's own license, any self-hosted translation model | Release blocked late | Review all three before the beta |

## Open questions

Five answers would lock this plan; until then I used the assumptions above.

- [ ] Which languages must work at launch, as source and as target?
- [ ] Android and iOS together, or one first? An Android-first launch removes the iOS 18 constraint from the critical path.
- [ ] Is a Flutter app acceptable, or does the team need pure Kotlin and Swift?
- [ ] Minimum iOS version: 16 (OCR only below 18) or 18 (full translation everywhere)?
- [ ] Is the cloud fallback allowed at all, or must every scan stay on the device?

## Sources

Checked on 2026-10-26.

- [PaddleOCR releases](https://github.com/PaddlePaddle/PaddleOCR/releases): PP-OCRv6 shipped with PaddleOCR 3.7.0 on 2026-06-11.
- [PP-OCRv6 on Hugging Face](https://huggingface.co/blog/PaddlePaddle/pp-ocrv6): tiers, parameter counts, accuracy, languages, ONNX and Paddle formats.
- [PP-OCRv6 Android deployment](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/android_deployment.html): SDK layout, toolchain versions, model folders, config.
- [PP-OCRv6 iOS deployment](https://www.paddleocr.ai/latest/en/version3.x/inference_deployment/cross_platform/ios_deployment.html): ONNX Runtime setup, ORT conversion, execution providers, benchmarks.
- [paddle\_ocr\_native on pub.dev](https://pub.dev/packages/paddle_ocr_native): Flutter plugin, supported ABIs, iOS simulator limit, license.
- [ML Kit on-device translation](https://developers.google.com/ml-kit/language/translation): language count, limits, English pivot.
- [Apple TranslationSession documentation](<https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:).md>) and an [Apple developer forum thread](https://developer.apple.com/forums/thread/813109) on error code 16.
- [Apple Translation framework overview](https://blakecrosley.com/es/blog/apple-translation-framework-on-device): iOS 17.4 and 18 surfaces, no simulator, language download (third-party write-up).
