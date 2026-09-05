/// Runs the YIN detector on a background isolate so a 3-million-MAC analysis
/// twenty times a second never lands on the UI thread.
///
/// Frames arrive from the microphone EventChannel on the main isolate; they
/// are forwarded to the worker, which keeps a rolling buffer, analyses every
/// [hop] new samples and posts a [PitchEstimate] (or null) back. If the
/// worker cannot be spawned (test harness), analysis runs inline instead.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'yin.dart';

class PitchWorker {
  PitchWorker._(this.sampleRate);

  final double sampleRate;

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  final StreamController<PitchEstimate?> _out = StreamController.broadcast();
  YinDetector? _inline;
  _RollingBuffer? _inlineBuffer;
  bool _disposed = false;

  /// Estimates, one per analysed hop. `null` means "no pitch in this hop".
  Stream<PitchEstimate?> get estimates => _out.stream;

  static Future<PitchWorker> start(double sampleRate) async {
    final w = PitchWorker._(sampleRate);
    try {
      final ready = ReceivePort();
      final from = ReceivePort();
      w._fromWorker = from;
      w._isolate = await Isolate.spawn<List<Object>>(
        _entry,
        [ready.sendPort, from.sendPort, sampleRate],
        debugName: 'tunekit-pitch',
      );
      w._toWorker = await ready.first as SendPort;
      ready.close();
      from.listen((msg) {
        if (w._disposed) return;
        if (msg == null) {
          w._out.add(null);
        } else if (msg is List) {
          w._out.add(PitchEstimate(
            frequency: msg[0] as double,
            confidence: msg[1] as double,
            rms: msg[2] as double,
          ));
        }
      });
    } catch (e) {
      debugPrint('pitch worker: isolate unavailable, running inline ($e)');
      w._isolate = null;
      w._inline = YinDetector(sampleRate: sampleRate);
      w._inlineBuffer = _RollingBuffer(w._inline!.requiredSamples);
    }
    return w;
  }

  void push(Float32List frame) {
    if (_disposed) return;
    final port = _toWorker;
    if (port != null) {
      port.send(frame);
      return;
    }
    final det = _inline;
    final buf = _inlineBuffer;
    if (det == null || buf == null) return;
    buf.append(frame);
    if (buf.sinceLastAnalysis >= _hopFor(det)) {
      buf.markAnalysed();
      _out.add(det.estimate(buf.snapshot()));
    }
  }

  void dispose() {
    _disposed = true;
    _toWorker?.send(null);
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _out.close();
  }

  static int _hopFor(YinDetector d) => 2048;

  static void _entry(List<Object> args) {
    final ready = args[0] as SendPort;
    final out = args[1] as SendPort;
    final sampleRate = args[2] as double;
    final det = YinDetector(sampleRate: sampleRate);
    final buf = _RollingBuffer(det.requiredSamples);
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((msg) {
      if (msg == null) {
        inbox.close();
        return;
      }
      if (msg is! Float32List) return;
      buf.append(msg);
      if (buf.sinceLastAnalysis < _hopFor(det)) return;
      buf.markAnalysed();
      final e = det.estimate(buf.snapshot());
      out.send(e == null ? null : [e.frequency, e.confidence, e.rms]);
    });
  }
}

/// Fixed-length FIFO of the most recent samples.
class _RollingBuffer {
  _RollingBuffer(this.length) : _data = Float32List(length);

  final int length;
  final Float32List _data;
  int _filled = 0;
  int sinceLastAnalysis = 0;

  void append(Float32List frame) {
    if (frame.length >= length) {
      _data.setRange(0, length, frame, frame.length - length);
      _filled = length;
    } else {
      final keep = length - frame.length;
      _data.setRange(0, keep, _data, frame.length);
      _data.setRange(keep, length, frame);
      _filled = (_filled + frame.length).clamp(0, length);
    }
    sinceLastAnalysis += frame.length;
  }

  void markAnalysed() => sinceLastAnalysis = 0;

  /// The buffer as-is; zeros until it has filled once, which YIN reads as
  /// silence rather than garbage.
  Float32List snapshot() => _filled < length ? Float32List(length) : _data;
}
