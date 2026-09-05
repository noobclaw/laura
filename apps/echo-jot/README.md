# echo_jot · 回声笔记 / EchoJot

Offline voice notes: tap the mic and talk. Two engines, both on the phone: the
system's on-device recognizer (text as you speak, no audio written) or a bundled
whisper.cpp model (transcribes after you stop; the temporary recording is deleted
once transcribed). No network permission, nothing downloaded, no recording kept.

- Product plan, architecture review and the device-acceptance checklist: [PLAN.md](PLAN.md)
- Store copy (zh + en): [store/listing.md](store/listing.md)

## How transcription works (the short version)

**System engine**: the OS on-device recognizer
(`SpeechRecognizer.createOnDeviceSpeechRecognizer`, API 31+ /
`SFSpeechRecognizer` with `requiresOnDeviceRecognition`), bridged in
[`DictationBridge.kt`](android/app/src/main/kotlin/com/noobclaw/echojot/DictationBridge.kt)
and [`DictationBridge.swift`](ios/Runner/DictationBridge.swift). It only listens
live (cannot read a saved file), so notes are dictated in real time and no audio
is written.

**Whisper engine** (1.2.0): `record` captures 16 kHz mono WAV, then
[`lib/tool/whisper_engine.dart`](lib/tool/whisper_engine.dart) runs whisper.cpp
via the `whisper_ggml` package against the bundled `ggml-base-q5_1.bin`
(~57 MB — **not in git**; `prepare_assets.sh` downloads and sha256-verifies it
before every build, run it once locally). Long takes are split into 60 s chunks
with 5 s overlap and merged ([`lib/tool/audio_chunks.dart`](lib/tool/audio_chunks.dart),
unit-tested). The WAV is deleted right after transcription.

There is deliberately **no cloud path** in either engine: if the system offers
no on-device recognition, the app says so and offers the Whisper engine.

Punctuation and sentence splitting are plain local Dart rules in
[`lib/tool/transcript_text.dart`](lib/tool/transcript_text.dart) (unit-tested).

## Build

```
flutter pub get && flutter analyze && flutter test
```

Release packaging runs in CI only (`.github/workflows/build-app.yml`, input
`app=apps/echo-jot`) — never on the 8GB dev machine (see PIPELINE.md).
