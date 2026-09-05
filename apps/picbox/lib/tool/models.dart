/// Container formats the toolbox understands.
enum ImageFormat { jpeg, png, webp, heic, unknown }

extension ImageFormatX on ImageFormat {
  String get extension => switch (this) {
        ImageFormat.jpeg => 'jpg',
        ImageFormat.png => 'png',
        ImageFormat.webp => 'webp',
        ImageFormat.heic => 'heic',
        ImageFormat.unknown => 'img',
      };

  String get label => switch (this) {
        ImageFormat.jpeg => 'JPEG',
        ImageFormat.png => 'PNG',
        ImageFormat.webp => 'WebP',
        ImageFormat.heic => 'HEIC',
        ImageFormat.unknown => '?',
      };

  /// Formats that can be written. HEIC is read-only in this app.
  bool get writable =>
      this == ImageFormat.jpeg || this == ImageFormat.png || this == ImageFormat.webp;

  bool get supportsQuality => this == ImageFormat.jpeg || this == ImageFormat.webp;

  static ImageFormat fromName(String? n) => ImageFormat.values.firstWhere(
        (f) => f.name == n,
        orElse: () => ImageFormat.jpeg,
      );
}

/// The six tools on the home grid.
enum ToolKind { compress, resize, convert, crop, metadata, watermark }

/// One imported picture, probed (header only) at import time.
class SourceImage {
  const SourceImage({
    required this.id,
    required this.path,
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    this.originalFormat,
  });

  final String id;

  /// Working file: the picked file itself, or a JPEG rendition for HEIC.
  final String path;

  /// Display name without directory, e.g. `IMG_0042.HEIC`.
  final String name;
  final int bytes;
  final int width;
  final int height;

  /// Format of [path].
  final ImageFormat format;

  /// Set when the picked file was converted on import (HEIC → JPEG).
  final ImageFormat? originalFormat;

  /// File name without extension, used to build output names.
  String get stem {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  ImageFormat get shownFormat => originalFormat ?? format;
}

/// Outcome of processing one [SourceImage].
class JobResult {
  const JobResult({
    required this.source,
    this.outputPath,
    this.outputBytes,
    this.outputWidth,
    this.outputHeight,
    this.outputFormat,
    this.error,
    this.note,
  });

  final SourceImage source;
  final String? outputPath;
  final int? outputBytes;
  final int? outputWidth;
  final int? outputHeight;
  final ImageFormat? outputFormat;

  /// User-facing failure reason (already localised), null on success.
  final String? error;

  /// Optional user-facing remark on success, e.g. "could not reach target".
  final String? note;

  bool get ok => error == null && outputPath != null;
}
