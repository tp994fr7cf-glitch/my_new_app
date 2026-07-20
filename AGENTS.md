# AGENTS.md

## Cursor Cloud specific instructions

This is a **Flutter** (Dart) e-learning app backed by **Firebase**. The primary/deployed target is **web**; Android/iOS/desktop scaffolding also exists.

### Toolchain (already installed in the VM snapshot)
- Flutter **stable** (SDK 3.44.7 / Dart 3.12.2) lives at `$HOME/flutter` and is on `PATH` via `~/.bashrc`. `pubspec.yaml` requires Dart `^3.12.0`.
- Google Chrome is at `/usr/local/bin/google-chrome`. For `flutter run -d chrome` set `CHROME_EXECUTABLE=/usr/local/bin/google-chrome`.
- The startup update script runs `flutter pub get`; no manual dependency install is needed.

### Run / lint / test / build (standard Flutter commands)
- Run web dev server (headless-friendly): `flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0`. First compile takes ~30–60s; it prints `lib/main.dart is being served at http://0.0.0.0:8080`. Open that URL in Chrome (via computer use) to test.
- Alternatively `flutter run -d chrome` launches Chrome directly (needs `CHROME_EXECUTABLE`).
- Lint: `flutter analyze` (reports only info/warning; no errors currently).
- Test: `flutter test`. Build web (release): `flutter build web --release`.

### Firebase: this app talks to the LIVE project (no emulators)
- `lib/firebase_options.dart` points directly at the production Firebase project `my-new-app-naona-20260523`. There is **no** Firebase Emulator config in the repo. Any auth/signup or Firestore/Storage action performed while testing writes to **production data** — use throwaway/test accounts and avoid polluting real data.
- Auth methods on the login page: Email/Password (works out of the box, no email-verification gate), Google Sign-In, and Phone/SMS. Email/Password signup (`メールアドレスで新規登録`) is the simplest way to reach the app as a new user; it routes to a role-selection onboarding, then the learner/teacher home.

### Testing notes (non-obvious)
- `flutter test` has a small number of pre-existing failures in this headless Cloud environment (e.g. some cases in `test/lesson_notes_page_test.dart` and `test/lesson_questions_page_test.dart`). These fail on clean `main` too and are unrelated to code changes; running individual test files generally passes. See `docs/agent-handoff.md`.
- A harmless diagnostic `debugPrint` with prefix `[LessonMediaSwitchDebug]` is intentionally left in `lib/services/lesson_media_playlist_playback.dart` and `lesson_media_playback.dart` (per handoff); do not treat it as accidental.

### Project context
- `docs/agent-handoff.md` (Japanese) is the authoritative handoff: user preferences (respond in Japanese, beginner-friendly), the audio⇄video switching bug that is intentionally **on hold** (do not proactively work on it), and manual `firebase deploy` guidance for rules. Read it before non-trivial work.
