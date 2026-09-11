import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models.dart';
import 'asterism.dart';
import 'output.dart';
import 'stack.dart';
import 'stars.dart';
import 'stretch.dart';
import 'transform.dart';
import 'warp.dart';

/// Where a run currently is. Drives the progress screen.
enum RunPhase { idle, preparing, aligning, stacking, finishing, done, failed, cancelled }

/// Whole-run failures — the ones that stop everything, as opposed to a
/// single frame that could not be aligned.
enum RunFailure {
  referenceUnreadable,
  referenceTooLarge,
  referenceTooFewStars,
  referenceTooBright,
  notEnoughAligned,
  diskFull,
  unknown,
}

/// Peak pixels a single frame may have.
///
/// The decode is pure Dart and transient: an RGBA buffer plus the packed RGB
/// copy is roughly 7 bytes per pixel. At 26 MP that is ~185 MB, which a phone
/// survives; a 108 MP or 200 MP sensor file would be ~750 MB and the process
/// is simply killed — not an exception anything could catch. So the cap is
/// checked from the container header, before a single pixel is allocated.
///
/// 26 MP, not 24: the iPhone 15 Pro and the 16 family shoot 5712x4284 by
/// default, which is 24,470,208 pixels — a hair OVER a 24 MP cap. With that
/// cap the reference frame of a stack shot on the current mainstream iPhone
/// fails the header check, `RunFailure.referenceTooLarge` aborts the whole
/// run, and the app cannot complete a single job on the device an App Review
/// engineer is holding. Raising the ceiling is the cheap half of the fix; the
/// other half (making "half resolution" apply at decode time, so it actually
/// rescues oversized frames instead of only shrinking after the allocation)
/// is M2 — see PLAN.md.
const int kMaxFramePixels = 26000000;

/// Frames below this many aligned members are not worth stacking — with one
/// frame there is nothing to average.
const int kMinStackFrames = 2;

/// Runs the whole align → stack → finish pipeline, one background isolate
/// per unit of work.
///
/// Cancellation is checked at every unit boundary (one frame, one band).
/// That bounds the stop latency at roughly one frame's decode — a few
/// seconds — without a long-lived isolate and the state synchronisation
/// that would come with it.
class StackRunner extends ChangeNotifier {
  RunPhase phase = RunPhase.idle;
  RunFailure? failure;

  /// Free-text detail for [failure] (a file-system message, say).
  String? failureDetail;

  int current = 0;
  int total = 1;
  final List<FrameReport> reports = [];
  StackOutcome? outcome;

  bool _cancelled = false;
  bool _disposed = false;
  Directory? _dir;

  bool get isRunning =>
      phase == RunPhase.preparing ||
      phase == RunPhase.aligning ||
      phase == RunPhase.stacking ||
      phase == RunPhase.finishing;

  /// Progress within the current phase.
  double get fraction => total <= 0 ? 0 : (current / total).clamp(0.0, 1.0);

  /// Progress across the whole run. Aligning owns the first 70 % (it decodes
  /// every frame), combining the rest — otherwise the ring fills up, resets
  /// to zero and looks like the run started over.
  double get overallFraction => switch (phase) {
        RunPhase.idle || RunPhase.preparing => 0,
        RunPhase.aligning => fraction * 0.7,
        RunPhase.stacking => 0.7 + fraction * 0.3,
        RunPhase.finishing || RunPhase.done => 1,
        // A stopped or failed run keeps the ring where it got to.
        RunPhase.failed || RunPhase.cancelled => _lastOverall,
      };

  double _lastOverall = 0;

  /// True once [cancel] was called and the run has not stopped yet — the UI
  /// says "stopping" rather than leaving the button looking unresponsive
  /// (the in-flight frame still has to finish; see the class comment).
  bool get isStopping => _cancelled && isRunning;

  void cancel() {
    if (_disposed || !isRunning) return;
    _cancelled = true;
    notifyListeners();
  }

  @override
  void dispose() {
    // The last isolate can still be in flight when the screen goes away; a
    // notify after dispose is an assertion failure in debug builds.
    _disposed = true;
    _cancelled = true;
    super.dispose();
  }

  void _set(RunPhase p, {int? current, int? total}) {
    phase = p;
    if (current != null) this.current = current;
    if (total != null) this.total = total;
    if (isRunning) _lastOverall = overallFraction;
    if (_disposed) return;
    notifyListeners();
  }

  /// Discard the scratch files of a finished run.
  Future<void> disposeRun() async {
    final d = _dir;
    _dir = null;
    if (d == null) return;
    try {
      await d.delete(recursive: true);
    } catch (e) {
      debugPrint('run cleanup skipped: $e');
    }
  }

  /// Align [frames] onto `frames[referenceIndex]` and combine them.
  ///
  /// Returns the stack, or null when the run failed or was cancelled — in
  /// both cases [phase] and [failure] say why, and [reports] keeps whatever
  /// per-frame verdicts were already reached (a stopped run must not throw
  /// away what it learned).
  Future<StackOutcome?> run({
    required List<SourceFrame> frames,
    required int referenceIndex,
    required StackSettings settings,
  }) async {
    _cancelled = false;
    failure = null;
    failureDetail = null;
    outcome = null;
    reports.clear();
    final divisor = settings.scale.divisor;
    _set(RunPhase.preparing, current: 0, total: frames.length);

    await disposeRun();
    final dir = await WorkDirs.fresh('run');
    _dir = dir;

    final ref = frames[referenceIndex];
    final refBaked = ref.orientationBaked;
    _PreparedReference prepared;
    try {
      prepared = await Isolate.run(() =>
          _prepareReference(ref.path, divisor, '${dir.path}/000.raw', refBaked));
    } on _DiskFull catch (e) {
      return _fail(RunFailure.diskFull, e.detail);
    } on _TooLarge {
      return _fail(RunFailure.referenceTooLarge);
    } catch (e) {
      debugPrint('reference prepare failed: $e');
      return _fail(RunFailure.referenceUnreadable, '$e');
    }
    if (prepared.overloaded) return _fail(RunFailure.referenceTooBright);
    if (prepared.stars.length < 3) return _fail(RunFailure.referenceTooFewStars);

    final aligned = <AlignedFrame>[
      AlignedFrame(
        path: '${dir.path}/000.raw',
        transform: Similarity.identity,
        sourceWidth: prepared.width,
        sourceHeight: prepared.height,
      ),
    ];
    reports.add(FrameReport(
      frameId: ref.id,
      name: ref.name,
      isReference: true,
      starsDetected: prepared.detected,
      matchedStars: prepared.stars.length,
      score: 100,
    ));
    _set(RunPhase.aligning, current: 1);

    final refStars = prepared.stars;
    var index = 0;
    for (final f in frames) {
      if (_cancelled) return _cancel();
      index++;
      if (identical(f, ref)) continue;
      final outPath = '${dir.path}/${index.toString().padLeft(3, '0')}.raw';
      final baked = f.orientationBaked;
      final path = f.path;
      _AlignOutcome res;
      try {
        res = await Isolate.run(() => _alignFrame(
              path: path,
              divisor: divisor,
              orientationBaked: baked,
              outPath: outPath,
              refStars: refStars,
              refWidth: prepared.width,
              refHeight: prepared.height,
            ));
      } on _DiskFull catch (e) {
        return _fail(RunFailure.diskFull, e.detail);
      } catch (e) {
        debugPrint('align failed for ${f.name}: $e');
        res = const _AlignOutcome.failed(AlignFailure.decodeFailed);
      }
      if (res.failure == null && res.transform != null) {
        aligned.add(AlignedFrame(
          path: outPath,
          transform: res.transform!,
          sourceWidth: res.sourceWidth,
          sourceHeight: res.sourceHeight,
        ));
      }
      reports.add(FrameReport(
        frameId: f.id,
        name: f.name,
        starsDetected: res.starsDetected,
        matchedStars: res.matchedStars,
        rmsPixels: res.rmsPixels,
        shiftPixels: res.transform?.shiftPixels ?? 0,
        rotationDegrees: res.transform?.rotationDegrees ?? 0,
        score: res.score,
        failure: res.failure,
      ));
      _set(RunPhase.aligning, current: reports.length);
    }

    if (_cancelled) return _cancel();
    if (aligned.length < kMinStackFrames) return _fail(RunFailure.notEnoughAligned);

    // ---- Combine, one horizontal band at a time. ----
    final w = prepared.width;
    final h = prepared.height;
    final stackedPath = '${dir.path}/stacked.raw';
    final bands = (h + kStackBandRows - 1) ~/ kStackBandRows;
    _set(RunPhase.stacking, current: 0, total: bands);
    RandomAccessFile out;
    try {
      out = await File(stackedPath).open(mode: FileMode.write);
    } catch (e) {
      return _fail(RunFailure.diskFull, '$e');
    }
    try {
      final mode = settings.mode;
      for (var b = 0; b < bands; b++) {
        if (_cancelled) return _cancel();
        final y0 = b * kStackBandRows;
        final y1 = (y0 + kStackBandRows) > h ? h : y0 + kStackBandRows;
        final band = await Isolate.run(() => stackBand(aligned, w, y0, y1, mode));
        await out.writeFrom(band);
        _set(RunPhase.stacking, current: b + 1);
      }
    } on FileSystemException catch (e) {
      return _fail(RunFailure.diskFull, e.message);
    } catch (e) {
      debugPrint('stack failed: $e');
      return _fail(RunFailure.unknown, '$e');
    } finally {
      try {
        await out.close();
      } catch (_) {}
    }

    if (_cancelled) return _cancel();
    _set(RunPhase.finishing, current: 0, total: 1);
    final result = StackOutcome(
      rawPath: stackedPath,
      width: w,
      height: h,
      reports: List.of(reports),
      usedFrames: aligned.length,
      mode: settings.mode,
    );
    outcome = result;
    _set(RunPhase.done, current: 1, total: 1);
    return result;
  }

  StackOutcome? _fail(RunFailure f, [String? detail]) {
    failure = f;
    failureDetail = detail;
    _set(RunPhase.failed);
    return null;
  }

  StackOutcome? _cancel() {
    _set(RunPhase.cancelled);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Isolate entry points. Plain data in, plain data out.
// ---------------------------------------------------------------------------

class _PreparedReference {
  const _PreparedReference(
      this.width, this.height, this.stars, this.detected, this.overloaded);
  final int width;
  final int height;

  /// The brightest [kMaxControlPoints] of them, used for matching.
  final List<Star> stars;

  /// How many sources were actually detected, before the control-point cap —
  /// this is the number the report shows, because "50" on every frame is not
  /// information.
  final int detected;
  final bool overloaded;
}

class _AlignOutcome {
  const _AlignOutcome({
    required this.transform,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.starsDetected,
    required this.matchedStars,
    required this.rmsPixels,
    required this.score,
  }) : failure = null;

  const _AlignOutcome.failed(this.failure, {this.starsDetected = 0})
      : transform = null,
        sourceWidth = 0,
        sourceHeight = 0,
        matchedStars = 0,
        rmsPixels = 0,
        score = 0;

  final Similarity? transform;
  final int sourceWidth;
  final int sourceHeight;
  final int starsDetected;
  final int matchedStars;
  final double rmsPixels;
  final int score;
  final AlignFailure? failure;
}

/// Raised when a scratch write fails, so the runner can say "disk full"
/// instead of a generic error.
class _DiskFull implements Exception {
  _DiskFull(this.detail);
  final String detail;
  @override
  String toString() => 'DiskFull($detail)';
}

/// Raised before any pixel buffer is allocated, when the frame has more
/// pixels than [kMaxFramePixels].
class _TooLarge implements Exception {
  @override
  String toString() => 'TooLarge()';
}

_PreparedReference _prepareReference(
    String path, int divisor, String outPath, bool orientationBaked) {
  final loaded = _loadRgb(path, divisor, orientationBaked);
  _writeRaw(outPath, loaded.rgb);
  final field = detectStars(rgbToLuma(loaded.rgb, loaded.width, loaded.height),
      loaded.width, loaded.height);
  return _PreparedReference(
      loaded.width, loaded.height, field.stars, field.blobs, field.overloaded);
}

_AlignOutcome _alignFrame({
  required String path,
  required int divisor,
  required bool orientationBaked,
  required String outPath,
  required List<Star> refStars,
  required int refWidth,
  required int refHeight,
}) {
  _Loaded loaded;
  try {
    loaded = _loadRgb(path, divisor, orientationBaked);
  } on _DiskFull {
    rethrow;
  } on _TooLarge {
    return const _AlignOutcome.failed(AlignFailure.tooLarge);
  } catch (_) {
    return const _AlignOutcome.failed(AlignFailure.decodeFailed);
  }
  if (loaded.width != refWidth || loaded.height != refHeight) {
    return const _AlignOutcome.failed(AlignFailure.sizeMismatch);
  }
  final field = detectStars(rgbToLuma(loaded.rgb, loaded.width, loaded.height),
      loaded.width, loaded.height);
  if (field.overloaded) {
    return const _AlignOutcome.failed(AlignFailure.tooBright);
  }
  if (field.stars.length < 3) {
    return _AlignOutcome.failed(AlignFailure.tooFewStars,
        starsDetected: field.blobs);
  }
  AlignResult res;
  try {
    res = alignStars(field.stars, refStars);
  } on AlignException catch (e) {
    return _AlignOutcome.failed(e.failure, starsDetected: field.blobs);
  }
  final warped = warpRgb(loaded.rgb, loaded.width, loaded.height, res.transform);
  _writeRaw(outPath, warped);
  return _AlignOutcome(
    transform: res.transform,
    sourceWidth: loaded.width,
    sourceHeight: loaded.height,
    starsDetected: field.blobs,
    matchedStars: res.matchedStars,
    rmsPixels: res.rmsPixels,
    score: res.score,
  );
}

class _Loaded {
  const _Loaded(this.rgb, this.width, this.height);
  final Uint8List rgb;
  final int width;
  final int height;
}

/// Decode a file to packed RGB in upright orientation, optionally halved.
///
/// [orientationBaked] is set for renditions whose rotation is already in the
/// pixels; applying the EXIF tag there would rotate them a second time.
_Loaded _loadRgb(String path, int divisor, bool orientationBaked) {
  final bytes = File(path).readAsBytesSync();
  final probe = img.findDecoderForData(bytes)?.startDecode(bytes);
  if (probe != null && probe.width * probe.height > kMaxFramePixels) {
    throw _TooLarge();
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('decode failed');
  final upright = orientationBaked ? decoded : img.bakeOrientation(decoded);
  final rgb = upright.getBytes(order: img.ChannelOrder.rgb);
  final w = upright.width;
  final h = upright.height;
  if (divisor <= 1) return _Loaded(rgb, w, h);
  final ow = w ~/ divisor;
  final oh = h ~/ divisor;
  return _Loaded(downsampleRgb(rgb, w, h, divisor, outW: ow, outH: oh), ow, oh);
}

void _writeRaw(String path, Uint8List bytes) {
  try {
    File(path).writeAsBytesSync(bytes, flush: true);
  } on FileSystemException catch (e) {
    throw _DiskFull(e.osError?.message ?? e.message);
  }
}

// ---------------------------------------------------------------------------
// Post-processing: preview, tone measurement and export.
// ---------------------------------------------------------------------------

class StackPreview {
  const StackPreview({
    required this.rgb,
    required this.width,
    required this.height,
    required this.stats,
  });

  /// Packed RGB, before the tone curve, small enough to re-stretch on the UI
  /// isolate while a slider is being dragged.
  final Uint8List rgb;
  final int width;
  final int height;
  final ToneStats stats;
}

/// Longest side of the live preview. Big enough to judge stars on a phone
/// screen, small enough that a full re-stretch is a few milliseconds.
const int kPreviewMaxSide = 1280;

/// Read the finished stack back, measure its tone and build the preview.
Future<StackPreview> buildPreview(StackOutcome o) => Isolate.run(() {
      final raw = File(o.rawPath).readAsBytesSync();
      final stats = measureTone(raw);
      final longest = o.width > o.height ? o.width : o.height;
      final factor = (longest / kPreviewMaxSide).ceil().clamp(1, 32);
      final pw = factor <= 1 ? o.width : o.width ~/ factor;
      final ph = factor <= 1 ? o.height : o.height ~/ factor;
      final small = factor <= 1
          ? raw
          : downsampleRgb(raw, o.width, o.height, factor, outW: pw, outH: ph);
      return StackPreview(rgb: small, width: pw, height: ph, stats: stats);
    });

/// Apply the tone curve at full resolution and write a JPEG.
Future<String> exportJpeg({
  required StackOutcome outcome,
  required StretchParams params,
  required double skyLevel,
  required String outPath,
  int quality = 95,
}) =>
    Isolate.run(() {
      final raw = File(outcome.rawPath).readAsBytesSync();
      applyStretch(raw, raw, params, skyLevel);
      final image = img.Image.fromBytes(
        width: outcome.width,
        height: outcome.height,
        bytes: raw.buffer,
        bytesOffset: raw.offsetInBytes,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );
      final jpg = img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv444);
      File(outPath).writeAsBytesSync(jpg, flush: true);
      return outPath;
    });
