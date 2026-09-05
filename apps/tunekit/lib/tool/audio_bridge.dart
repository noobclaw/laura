/// Dart side of the app's own audio platform channel (no third-party audio
/// plugin). Kotlin: android/.../AudioBridge.kt, Swift: ios/Runner/AudioBridge.swift.
///
/// Contract:
///  MethodChannel `tunekit/audio`
///    micStatus            -> "granted" | "denied" | "permanentlyDenied" | "undetermined"
///    micRequest           -> same, after the system prompt
///    openSettings         -> null (app's page in system settings)
///    micStart             -> sampleRate (double); throws code "permission" | "mic_unavailable"
///    micStop              -> null (idempotent)
///    metroStart {bpm, beats, unit, subdivision, accents:[int]} -> null; throws "audio_unavailable"
///    metroUpdate {same}   -> null (applies from the next tick, phase kept)
///    metroStop            -> null (idempotent)
///  EventChannel `tunekit/audio/mic`    -> Float32List frames (mono, −1..1)
///  EventChannel `tunekit/audio/events` -> {type: tick|interrupted|error, ...}
///
/// The metronome is a sample-accurate sequencer inside the native render
/// callback (AudioTrack thread / AVAudioSourceNode). Tick events carry
/// `dueMs`, how far ahead of the speaker the tick was rendered, so the visual
/// flash can be delayed to land with the sound.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'music/metronome_math.dart';

enum MicPermission { granted, denied, permanentlyDenied, undetermined }

class MetroTick {
  const MetroTick({required this.index, required this.beat, required this.kind, required this.dueMs});
  final int index;
  final int beat;
  final TickKind kind;
  final double dueMs;
}

sealed class AudioEvent {
  const AudioEvent();
}

class TickEvent extends AudioEvent {
  const TickEvent(this.tick);
  final MetroTick tick;
}

/// The OS took the audio away (phone call, another app, headset unplugged
/// mid-recording). [what] is `mic`, `metro` or `all`.
class InterruptedEvent extends AudioEvent {
  const InterruptedEvent(this.what);
  final String what;
}

class AudioErrorEvent extends AudioEvent {
  const AudioErrorEvent(this.what, this.message);
  final String what;
  final String message;
}

class AudioBridge {
  AudioBridge._();
  static final AudioBridge instance = AudioBridge._();

  static const MethodChannel _method = MethodChannel('tunekit/audio');
  static const EventChannel _mic = EventChannel('tunekit/audio/mic');
  static const EventChannel _events = EventChannel('tunekit/audio/events');

  Stream<AudioEvent>? _eventStream;

  /// Every native event, broadcast.
  Stream<AudioEvent> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .map<AudioEvent?>((raw) {
        if (raw is! Map) return null;
        final type = raw['type'];
        switch (type) {
          case 'tick':
            final k = (raw['kind'] as num?)?.toInt() ?? 1;
            return TickEvent(MetroTick(
              index: (raw['index'] as num?)?.toInt() ?? 0,
              beat: (raw['beat'] as num?)?.toInt() ?? 0,
              kind: TickKind.values[k.clamp(0, TickKind.values.length - 1)],
              dueMs: (raw['dueMs'] as num?)?.toDouble() ?? 0,
            ));
          case 'interrupted':
            return InterruptedEvent(raw['what']?.toString() ?? 'all');
          case 'error':
            return AudioErrorEvent(
                raw['what']?.toString() ?? '', raw['message']?.toString() ?? '');
        }
        return null;
      })
      .where((e) => e != null)
      .cast<AudioEvent>()
      .asBroadcastStream();

  /// Microphone frames. Subscribing starts nothing by itself — call
  /// [micStart] first; cancelling the subscription does not stop capture.
  Stream<Float32List> get micFrames => _mic.receiveBroadcastStream().map((raw) {
        if (raw is Float32List) return raw;
        if (raw is Float64List) return Float32List.fromList(raw);
        if (raw is List) return Float32List.fromList(raw.cast<num>().map((n) => n.toDouble()).toList());
        return Float32List(0);
      });

  static MicPermission _parse(Object? v) => switch (v) {
        'granted' => MicPermission.granted,
        'denied' => MicPermission.denied,
        'permanentlyDenied' => MicPermission.permanentlyDenied,
        _ => MicPermission.undetermined,
      };

  Future<MicPermission> micStatus() async {
    try {
      return _parse(await _method.invokeMethod<String>('micStatus'));
    } on MissingPluginException {
      return MicPermission.undetermined;
    }
  }

  Future<MicPermission> micRequest() async {
    try {
      return _parse(await _method.invokeMethod<String>('micRequest'));
    } on MissingPluginException {
      return MicPermission.undetermined;
    }
  }

  Future<void> openSettings() async {
    try {
      await _method.invokeMethod<void>('openSettings');
    } catch (e) {
      debugPrint('openSettings failed: $e');
    }
  }

  /// Starts capture; resolves to the capture sample rate.
  Future<double> micStart() async {
    final rate = await _method.invokeMethod<num>('micStart');
    return (rate ?? 44100).toDouble();
  }

  Future<void> micStop() async {
    try {
      await _method.invokeMethod<void>('micStop');
    } on MissingPluginException {
      // test harness
    }
  }

  Map<String, Object> _metroArgs(int bpm, TimeSignature sig, Subdivision sub) => {
        'bpm': bpm,
        'beats': sig.beats,
        'unit': sig.unit,
        'subdivision': sub.perBeat,
        'accents': sig.accents.toList()..sort(),
      };

  Future<void> metroStart(int bpm, TimeSignature sig, Subdivision sub) =>
      _method.invokeMethod<void>('metroStart', _metroArgs(bpm, sig, sub));

  Future<void> metroUpdate(int bpm, TimeSignature sig, Subdivision sub) =>
      _method.invokeMethod<void>('metroUpdate', _metroArgs(bpm, sig, sub));

  Future<void> metroStop() async {
    try {
      await _method.invokeMethod<void>('metroStop');
    } on MissingPluginException {
      // test harness
    }
  }
}
