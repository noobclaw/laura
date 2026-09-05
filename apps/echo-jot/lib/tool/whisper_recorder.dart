import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Microphone capture for the Whisper engine: 16 kHz mono PCM16 WAV, the
/// exact layout whisper.cpp consumes, so no resampling happens afterwards.
///
/// Built on the `record` package the way autosnore uses it. iOS notes from
/// there that apply here: the plugin owns the AVAudioSession while
/// recording; `pauseResume` lets a phone call pause and resume the file
/// instead of killing it; the system recognizer bridge deactivates its own
/// session on stop, so the two engines never fight over the microphone.
///
/// The recorder is created lazily: constructing `AudioRecorder` touches the
/// platform channel, which must not happen in widget tests or before the
/// user picks this engine.
class WhisperRecorder {
  AudioRecorder? _rec;
  StreamSubscription<Amplitude>? _amp;

  static const int sampleRate = 16000;

  /// How often the level meter is fed; matches the system engine's cadence.
  static const Duration levelInterval = Duration(milliseconds: 120);

  bool get active => _amp != null;

  AudioRecorder get _recorder => _rec ??= AudioRecorder();

  /// Starts writing [path]. [onLevel] receives the current peak in dBFS
  /// (≈ -60 silence … 0 clipping). Throws on any platform failure — the
  /// controller turns that into a visible message.
  Future<void> start(String path,
      {required void Function(double dbfs) onLevel}) async {
    final rec = _recorder;
    await rec.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: 1,
        // Dictation is one voice close to the phone; AGC evens out a speaker
        // who leans back, and the OS noise suppressor helps outdoors. Both
        // are best-effort flags the platform may ignore.
        autoGain: true,
        noiseSuppress: true,
        audioInterruption: Platform.isIOS
            ? AudioInterruptionMode.pauseResume
            : AudioInterruptionMode.pause,
        iosConfig: const IosRecordConfig(
          categoryOptions: [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
          ],
        ),
      ),
      path: path,
    );
    await _amp?.cancel();
    _amp = rec.onAmplitudeChanged(levelInterval).listen(
      (a) => onLevel(a.current),
      onError: (Object e) => debugPrint('amplitude stream error: $e'),
    );
  }

  /// Whether the platform reports a recording in progress — for the stall
  /// check when the user stops a session the OS may already have killed.
  Future<bool> isRecording() async {
    try {
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  /// Finishes the file and returns its path (null when nothing was written).
  Future<String?> stop() async {
    await _amp?.cancel();
    _amp = null;
    try {
      return await _recorder.stop();
    } catch (e) {
      debugPrint('recorder stop failed: $e');
      return null;
    }
  }

  /// Stops and deletes the file.
  Future<void> cancel() async {
    await _amp?.cancel();
    _amp = null;
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('recorder cancel failed: $e');
    }
  }

  Future<void> dispose() async {
    await _amp?.cancel();
    _amp = null;
    final rec = _rec;
    _rec = null;
    if (rec != null) {
      try {
        await rec.dispose();
      } catch (e) {
        debugPrint('recorder dispose failed: $e');
      }
    }
  }
}
