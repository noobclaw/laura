import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/l10n.dart';
import '../models.dart';
import 'output.dart';

/// What an import attempt produced: the usable frames plus one localised
/// line per file that had to be skipped. Never silent.
class ImportResult {
  const ImportResult({
    required this.frames,
    required this.skipped,
    this.scratchDir,
    this.error,
    this.permissionDenied = false,
  });
  final List<SourceFrame> frames;
  final List<String> skipped;

  /// Set when HEIC renditions were written; the caller owns it and must
  /// delete it once the frames are no longer needed.
  final String? scratchDir;

  /// Whole-import failure (picker unavailable, permission), or null.
  final String? error;
  final bool permissionDenied;
}

/// Header facts + EXIF exposure, read off the UI thread.
class _Probe {
  const _Probe(this.format, this.width, this.height, this.bytes, this.iso,
      this.exposure, this.focal);
  final SourceFormat format;
  final int width;
  final int height;
  final int bytes;
  final int? iso;
  final double? exposure;
  final double? focal;
}

/// Imports through the system pickers, which need no storage permission on
/// either platform (PHPicker / Android Photo Picker). HEIC is turned into a
/// JPEG rendition by the platform codec so the pure-Dart decoder downstream
/// always sees something it understands.
class FrameImporter {
  FrameImporter();

  final ImagePicker _picker = ImagePicker();
  int _seq = 0;

  Future<ImportResult> pickFromLibrary() async {
    List<XFile> files;
    try {
      files = await _picker.pickMultiImage(requestFullMetadata: true);
    } on PlatformException catch (e) {
      return ImportResult(
          frames: const [],
          skipped: const [],
          error: _pickerError(e),
          permissionDenied: e.code == 'photo_access_denied');
    } catch (e) {
      return ImportResult(
          frames: const [],
          skipped: const [],
          error: '${tr(zh: '无法打开相册', en: 'Could not open the photo library')}: $e');
    }
    return _ingest(files);
  }

  String _pickerError(PlatformException e) => switch (e.code) {
        'photo_access_denied' => tr(
            zh: '没有相册访问权限。请在系统设置里允许本应用访问照片。',
            en: 'Photos permission was denied. Allow photo access for this app in system settings.'),
        _ => '${tr(zh: '选择照片失败', en: 'Could not pick photos')}: ${e.message ?? e.code}',
      };

  Future<ImportResult> _ingest(List<XFile> files) async {
    if (files.isEmpty) return const ImportResult(frames: [], skipped: []);
    final frames = <SourceFrame>[];
    final skipped = <String>[];
    Directory? convDir;
    for (final f in files) {
      final name = _displayName(f);
      try {
        var probe = await _probeFile(f.path);
        var path = f.path;
        var baked = false;
        if (probe.format == SourceFormat.heic ||
            (probe.width <= 0 && probe.format == SourceFormat.unknown)) {
          convDir ??= await WorkDirs.fresh('import');
          // `autoCorrectionAngle` bakes the rotation into the pixels while
          // `keepExif` carries the original orientation tag along with them.
          // Both are wanted — the tag is where ISO and shutter live, and the
          // exposure-outlier check needs them — so the rendition is marked
          // as already-upright and nothing downstream rotates it again.
          final out = await FlutterImageCompress.compressWithFile(
            f.path,
            minWidth: 1 << 20,
            minHeight: 1 << 20,
            quality: 96,
            format: CompressFormat.jpeg,
            keepExif: true,
            autoCorrectionAngle: true,
          );
          if (out == null || out.isEmpty) {
            skipped.add(
                '$name: ${tr(zh: '系统无法解码这张 HEIC 照片,请改用 JPEG 导出后再试', en: 'the system could not decode this HEIC photo — export it as JPEG and try again')}');
            continue;
          }
          _seq++;
          final jpgPath = '${convDir.path}/${_seq}_${_asciiStem(name)}.jpg';
          await File(jpgPath).writeAsBytes(out, flush: true);
          path = jpgPath;
          probe = await _probeFile(jpgPath, orientationBaked: true);
          baked = true;
        }
        if (probe.width <= 0 || probe.height <= 0) {
          skipped.add('$name: ${tr(zh: '不是可识别的图片', en: 'not a recognisable image')}');
          continue;
        }
        _seq++;
        frames.add(SourceFrame(
          id: '${DateTime.now().microsecondsSinceEpoch}-$_seq',
          path: path,
          name: name,
          bytes: probe.bytes,
          width: probe.width,
          height: probe.height,
          format: probe.format,
          orientationBaked: baked,
          iso: probe.iso,
          exposureSeconds: probe.exposure,
          focalMm: probe.focal,
        ));
      } catch (e) {
        debugPrint('import failed for $name: $e');
        skipped.add('$name: ${tr(zh: '读取失败', en: 'could not be read')}');
      }
    }
    return ImportResult(frames: frames, skipped: skipped, scratchDir: convDir?.path);
  }

  String _asciiStem(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return safe.isEmpty ? 'frame' : safe;
  }

  String _displayName(XFile f) {
    var n = f.name.trim();
    if (n.isEmpty) n = f.path.split(RegExp(r'[\\/]')).last;
    if (n.startsWith('image_picker_')) {
      final ext = n.contains('.') ? n.substring(n.lastIndexOf('.')) : '';
      n = 'IMG_${(++_seq + 1000).toString().substring(1)}$ext';
    }
    return n;
  }
}

Future<_Probe> _probeFile(String path, {bool orientationBaked = false}) =>
    Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      return _probeBytes(bytes, orientationBaked: orientationBaked);
    });

_Probe _probeBytes(Uint8List bytes, {bool orientationBaked = false}) {
  final format = _sniff(bytes);
  var w = 0;
  var h = 0;
  var orientation = 1;
  int? iso;
  double? exposure;
  double? focal;
  try {
    final dec = img.findDecoderForData(bytes);
    final info = dec?.startDecode(bytes);
    w = info?.width ?? 0;
    h = info?.height ?? 0;
    if (format == SourceFormat.jpeg) {
      final exif = img.decodeJpgExif(bytes);
      if (exif != null) {
        orientation = (exif.imageIfd.orientation ?? 1).clamp(1, 8);
        // Numeric tags: 0x829a ExposureTime, 0x8827 ISO, 0x920a FocalLength.
        exposure = exif.exifIfd[0x829a]?.toDouble();
        iso = exif.exifIfd[0x8827]?.toInt();
        focal = exif.exifIfd[0x920a]?.toDouble();
      }
    }
  } catch (_) {
    // A truncated header reports 0×0; the caller rejects it with a readable
    // message instead of crashing here.
  }
  if (!orientationBaked && orientation >= 5 && orientation <= 8) {
    final t = w;
    w = h;
    h = t;
  }
  if (exposure != null && (exposure <= 0 || !exposure.isFinite)) exposure = null;
  if (iso != null && iso <= 0) iso = null;
  if (focal != null && (focal <= 0 || !focal.isFinite)) focal = null;
  return _Probe(format, w, h, bytes.length, iso, exposure, focal);
}

SourceFormat _sniff(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return SourceFormat.jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return SourceFormat.png;
  }
  if (b.length >= 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    final brand = String.fromCharCodes(b, 8, 12).toLowerCase();
    if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('msf')) {
      return SourceFormat.heic;
    }
  }
  return SourceFormat.unknown;
}
