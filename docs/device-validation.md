# Device validation

Use physical arm64 devices; the OCR dependency does not support the iOS simulator
or x86 Android emulators. Never substitute fake engine tests for these checks.

1. Run `flutter test integration_test/device_smoke_test.dart -d DEVICE_ID` with
   network disabled after the app is installed. OCR should return HELLO from the
   image drawn by the test. This does not download translation packs.
2. Launch the app normally. Download English → your target through Language packs.
   Disable network, capture a 20-line page, and verify original text, translation,
   tap-to-toggle overlay, correction, copy, restart/history and deletion.
3. With no installed pair, scan again. OCR must stay in history; translation must
   explain that a download is needed. Download explicitly, return, tap Translate.
4. Cancel downloads and deny the camera permission. Check recovery. On Android,
   recreate the activity while the camera is foregrounded and recover the image.
5. Share a JPEG from Photos to Lensling with the app closed and already open.
   On iOS, tap Done in the extension and return to Lensling to consume the photo.
6. Test EXIF rotations 1–8, large photos, corrupt/unsupported files, no text,
   mixed languages, separate columns, vertical Japanese, and strong rotation.
7. Repeat 20 captures. Profile cold start, peak memory and thermals. Warm up 3 runs,
   then report median detection/recognition latency from 10 comparable photos.

For accuracy, create a consented corpus with one expected JSON record per image:
image ID, source language, desktop text, desktop polygons, and desktop engine and
model hashes. Compare phone text using character error rate on normalized Unicode.
Keep personal images out of the public repository. The corpus is not supplied by
the implementation plan and must be collected before making parity claims.

For translation, have native speakers score at least 50 sentences per launch pair.
Test short strings where language identification is ambiguous and manually select
the source. Non-English ML Kit pairs use English as a pivot.
