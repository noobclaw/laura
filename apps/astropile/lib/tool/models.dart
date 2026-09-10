import 'engine/asterism.dart';
import 'engine/stack.dart';

/// Container formats the importer understands.
enum SourceFormat { jpeg, png, heic, unknown }

extension SourceFormatX on SourceFormat {
  String get label => switch (this) {
        SourceFormat.jpeg => 'JPEG',
        SourceFormat.png => 'PNG',
        SourceFormat.heic => 'HEIC',
        SourceFormat.unknown => '?',
      };
}

/// Resolution the stack is computed at. Half quarters both the time and the
/// scratch-disk footprint, which is the difference between "runs on a 3-year
/// -old phone with 4 GB free" and "fails at frame 20".
enum WorkScale { full, half }

extension WorkScaleX on WorkScale {
  int get divisor => this == WorkScale.full ? 1 : 2;
}

/// Why a frame is flagged before the run even starts.
enum FramePrecheck {
  ok,

  /// A different pixel size than the reference — cannot be stacked at all.
  sizeMismatch,

  /// Shot with different exposure settings than most of the batch. Usable,
  /// but it will pull the average; the user decides.
  exposureOutlier,
}

/// One imported frame.
class SourceFrame {
  const SourceFrame({
    required this.id,
    required this.path,
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    this.orientationBaked = false,
    this.iso,
    this.exposureSeconds,
    this.focalMm,
  });

  final String id;

  /// Working file — the picked file, or a JPEG rendition for HEIC.
  final String path;
  final String name;
  final int bytes;

  /// Upright dimensions (EXIF orientation already applied).
  final int width;
  final int height;
  final SourceFormat format;

  /// True for a HEIC rendition whose rotation is already in the pixels while
  /// the original orientation tag is still in the EXIF block. Applying that
  /// tag again would turn the whole burst sideways.
  final bool orientationBaked;

  final int? iso;
  final double? exposureSeconds;
  final double? focalMm;

  int get pixels => width * height;

  String get stem {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// `ISO 3200 · 1/4s · 26mm`, skipping whatever the file does not carry.
  String get exposureSummary {
    final parts = <String>[];
    if (iso != null) parts.add('ISO $iso');
    if (exposureSeconds != null) parts.add(formatShutter(exposureSeconds!));
    if (focalMm != null) parts.add('${focalMm!.round()}mm');
    return parts.join(' · ');
  }

  /// Two frames count as the same exposure when ISO and shutter both match.
  /// Focal length is deliberately excluded: a phone that switched lenses
  /// mid-burst is caught by the size check instead.
  String get exposureKey => '${iso ?? '?'}/${exposureSeconds?.toStringAsFixed(4) ?? '?'}';
}

String formatShutter(double seconds) {
  if (seconds >= 1) return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  final denom = (1 / seconds).round();
  return '1/$denom s';
}

String formatBytes(int b) {
  if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}

/// What the alignment pass learned about one frame — the wedge, and the only
/// screen in the app the competitors do not have.
class FrameReport {
  const FrameReport({
    required this.frameId,
    required this.name,
    this.isReference = false,
    this.starsDetected = 0,
    this.matchedStars = 0,
    this.rmsPixels = 0,
    this.shiftPixels = 0,
    this.rotationDegrees = 0,
    this.score = 0,
    this.failure,
  });

  final String frameId;
  final String name;
  final bool isReference;
  final int starsDetected;
  final int matchedStars;
  final double rmsPixels;
  final double shiftPixels;
  final double rotationDegrees;
  final int score;

  /// Null on success.
  final AlignFailure? failure;

  bool get ok => failure == null;
}

/// Everything the run needs, decided on the frames screen.
class StackSettings {
  const StackSettings({
    required this.mode,
    required this.scale,
  });
  final StackMode mode;
  final WorkScale scale;
}

/// A finished stack, held in memory as packed RGB so the tone sliders can be
/// re-applied without recomputing anything.
class StackOutcome {
  const StackOutcome({
    required this.rawPath,
    required this.width,
    required this.height,
    required this.reports,
    required this.usedFrames,
    required this.mode,
  });

  /// Packed RGB, `width × height × 3`, before the tone curve.
  final String rawPath;
  final int width;
  final int height;
  final List<FrameReport> reports;
  final int usedFrames;
  final StackMode mode;

  int get failedFrames => reports.where((r) => !r.ok).length;
}
