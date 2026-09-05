import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/l10n.dart';
import '../models.dart';
import 'jobs.dart';
import 'output.dart';

/// What an import attempt produced: the usable images plus one localised
/// message per file that had to be skipped (never silent).
class ImportResult {
  const ImportResult({required this.images, required this.skipped, this.error, this.permissionDenied = false, this.converted = 0});
  final List<SourceImage> images;
  final List<String> skipped;

  /// How many HEIC/HEIF files were handed over as (or turned into) JPEG.
  final int converted;

  /// Whole-import failure (picker unavailable, permission), or null.
  final String? error;
  final bool permissionDenied;
}

/// Imports through the system pickers, which need no storage permission on
/// either platform (PHPicker / Android Photo Picker). HEIC is converted to a
/// JPEG rendition on import so every tool downstream sees a format the
/// Dart codecs understand; the original format is remembered for display.
class ImageImporter {
  ImageImporter();

  final ImagePicker _picker = ImagePicker();
  int _seq = 0;

  Future<ImportResult> pickFromLibrary() async {
    List<XFile> files;
    try {
      files = await _picker.pickMultiImage(requestFullMetadata: true);
    } on PlatformException catch (e) {
      return ImportResult(images: const [], skipped: const [], error: _pickerError(e), permissionDenied: _isDenied(e));
    } catch (e) {
      return ImportResult(images: const [], skipped: const [], error: '${tr(zh: '无法打开相册', en: 'Could not open the photo library')}: $e');
    }
    return _ingest(files);
  }

  Future<ImportResult> captureFromCamera() async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: ImageSource.camera, requestFullMetadata: true);
    } on PlatformException catch (e) {
      return ImportResult(images: const [], skipped: const [], error: _pickerError(e), permissionDenied: _isDenied(e));
    } catch (e) {
      return ImportResult(images: const [], skipped: const [], error: '${tr(zh: '无法打开相机', en: 'Could not open the camera')}: $e');
    }
    if (file == null) return const ImportResult(images: [], skipped: []);
    return _ingest([file]);
  }

  bool _isDenied(PlatformException e) =>
      e.code == 'camera_access_denied' || e.code == 'photo_access_denied';

  String _pickerError(PlatformException e) => switch (e.code) {
        'camera_access_denied' => tr(
            zh: '没有相机权限。请在系统设置里允许本应用使用相机。',
            en: 'Camera permission was denied. Allow camera access for this app in system settings.'),
        'photo_access_denied' => tr(
            zh: '没有相册访问权限。请在系统设置里允许本应用访问照片。',
            en: 'Photos permission was denied. Allow photo access for this app in system settings.'),
        'no_available_camera' => tr(zh: '这台设备没有可用的相机', en: 'No camera is available on this device'),
        _ => '${tr(zh: '选择图片失败', en: 'Could not pick images')}: ${e.message ?? e.code}',
      };

  Future<ImportResult> _ingest(List<XFile> files) async {
    if (files.isEmpty) return const ImportResult(images: [], skipped: []);
    final images = <SourceImage>[];
    final skipped = <String>[];
    var converted = 0;
    Directory? convDir;
    for (final f in files) {
      final name = _displayName(f);
      try {
        final probe = await probeFile(f.path);
        var path = f.path;
        var fmt = probe.info.format;
        var w = probe.info.width;
        var h = probe.info.height;
        var bytes = probe.bytes;
        ImageFormat? original;
        // iOS hands HEIC over already converted to JPEG; the only trace is
        // the picker's file name / mime type when it keeps them.
        if (fmt == ImageFormat.jpeg && _looksHeic(f)) {
          original = ImageFormat.heic;
          converted++;
        }
        if (fmt == ImageFormat.heic || (fmt == ImageFormat.unknown && w == 0)) {
          // Native rendition: iOS ImageIO / Android BitmapFactory (API 28+).
          convDir ??= await WorkDirs.fresh('import');
          final out = await FlutterImageCompress.compressWithFile(
            f.path,
            minWidth: 1 << 20,
            minHeight: 1 << 20,
            quality: 95,
            format: CompressFormat.jpeg,
            keepExif: true,
            autoCorrectionAngle: true,
          );
          if (out == null || out.isEmpty) {
            skipped.add('$name: ${tr(zh: '系统无法解码(HEIC 需要 Android 9 以上)', en: 'the system could not decode it (HEIC needs Android 9+)')}');
            continue;
          }
          final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
          final jpgPath = '${convDir.path}/${_seq}_$stem.jpg';
          await File(jpgPath).writeAsBytes(out, flush: true);
          final p2 = await probeFile(jpgPath);
          original = fmt == ImageFormat.heic ? ImageFormat.heic : ImageFormat.unknown;
          if (original == ImageFormat.heic) converted++;
          path = jpgPath;
          fmt = ImageFormat.jpeg;
          w = p2.info.width;
          h = p2.info.height;
          bytes = p2.bytes;
        }
        if (w <= 0 || h <= 0) {
          skipped.add('$name: ${tr(zh: '不是可识别的图片', en: 'not a recognisable image')}');
          continue;
        }
        _seq++;
        images.add(SourceImage(
          id: '${DateTime.now().microsecondsSinceEpoch}-$_seq',
          path: path,
          name: name,
          bytes: bytes,
          width: w,
          height: h,
          format: fmt,
          originalFormat: original,
          orientation: fmt == ImageFormat.jpeg && path == f.path ? probe.info.orientation : 1,
        ));
      } catch (e) {
        debugPrint('import failed for $name: $e');
        skipped.add('$name: ${tr(zh: '读取失败', en: 'could not be read')}');
      }
    }
    return ImportResult(images: images, skipped: skipped, converted: converted);
  }

  bool _looksHeic(XFile f) {
    final n = '${f.name} ${f.path} ${f.mimeType ?? ''}'.toLowerCase();
    return n.contains('.heic') || n.contains('.heif') || n.contains('image/heic') || n.contains('image/heif');
  }

  String _displayName(XFile f) {
    var n = f.name.trim();
    if (n.isEmpty) n = f.path.split(RegExp(r'[\\/]')).last;
    // iOS hands back "image_picker_<uuid>.jpg"; shorten to something a human
    // can tell apart in the result list.
    if (n.startsWith('image_picker_')) {
      final ext = n.contains('.') ? n.substring(n.lastIndexOf('.')) : '';
      n = 'IMG_${(++_seq + 1000).toString().substring(1)}$ext';
    }
    return n;
  }
}
