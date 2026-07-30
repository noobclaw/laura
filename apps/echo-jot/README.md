# echo_jot — 回声笔记 / EchoJot

Offline voice notes: tap the mic, talk, and the text appears as you speak. No
network permission, no bundled speech model, and no audio file is ever stored.

- Product plan, architecture review and the device-acceptance checklist: [PLAN.md](PLAN.md)
- Store copy (zh + en): [store/listing.md](store/listing.md)

## How transcription works (the short version)

Dictation goes through the **Android system on-device recognizer**
(`SpeechRecognizer.createOnDeviceSpeechRecognizer`, API 31+), bridged in
[`android/app/src/main/kotlin/com/noobclaw/echojot/DictationBridge.kt`](android/app/src/main/kotlin/com/noobclaw/echojot/DictationBridge.kt).
There is deliberately **no cloud path**: if the system offers no on-device
recognition, the app says so and stops. Because that recognizer only listens
live (it cannot read a saved file), notes are dictated in real time and no audio
is kept.

Punctuation and sentence splitting are plain local Dart rules in
[`lib/tool/transcript_text.dart`](lib/tool/transcript_text.dart) (unit-tested).

## Build

```
flutter pub get && flutter analyze && flutter test
```

Release packaging runs in CI only (`.github/workflows/build-app.yml`, input
`app=apps/echo-jot`) — never on the 8GB dev machine (see PIPELINE.md).
