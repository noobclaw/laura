# TuneBench / 调音节拍器

Tuner + metronome + chord/scale practice + practice log. Fully offline, one-time Pro unlock.
See `PLAN.md` for the design, reference-implementation analysis, audit notes and the device checklist; `store/listing.md` for store copy.

- Dart: `lib/tool/` (ToolModule contract from the shell). Music theory in `lib/tool/music/`, YIN pitch detection in `lib/tool/pitch/`.
- Native audio (own platform channel, no plugin): `android/.../AudioBridge.kt`, `ios/Runner/AudioBridge.swift`; contract in `lib/tool/audio_bridge.dart`.
- Icons: `node apps/tunekit/store/make_icons.mjs` (uses sharp from `D:/noob/backend`).
- Checks: `flutter analyze` (0 issues) and `flutter test` (PUB_CACHE=D:\dev\pub-cache). Never `flutter build` on the 8 GB machine — CI builds.
