# Publishing the repository

The local repository uses the `main` branch. The initial source snapshot includes
the app, tests, native Android/iOS hosts, model checksums and a GitHub Actions
workflow. The application's own license remains undecided.

## Connect and push

Create an empty repository on your Git hosting service using your chosen name
and visibility. Leave its generated README, license and gitignore options off
because the local project already contains its own files.

From this project directory, replace `REPOSITORY_URL` with the repository's Git URL:

```sh
git remote add origin REPOSITORY_URL
git push -u origin main
```

If `origin` is already configured, inspect it with `git remote -v` before changing
it. Use your normal Git credential manager or SSH setup; never put a token into
the repository URL or commit credentials.

## Included and excluded files

Track `pubspec.lock`, the Gradle wrapper scripts/JAR/properties, Flutter project
metadata, source, tests, assets and documentation. Local Flutter/Android SDKs under
`.tools`, generated plugin files, `.dart_tool`, build output, CocoaPods, IDE state,
environment files and signing material are ignored.

The model weights come from `paddle_ocr_native` 0.1.1 during `flutter pub get`.
Their checksums are committed in `models.lock.json`. Run:

```sh
flutter pub get --enforce-lockfile
python scripts/verify_models.py
flutter analyze
flutter test
```

GitHub Actions runs formatting, analysis, tests, model verification and an arm64
Android debug build for pushes and pull requests. The APK is uploaded as a workflow
artifact rather than committed to Git. The workflow has read-only repository
permissions and does not require signing secrets.

Publishing the source does not configure Android release signing, Apple signing
or App Groups. Those steps remain in the README and device validation checklist.
