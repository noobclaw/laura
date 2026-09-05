import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../models.dart';

/// Output name: `<original stem>_<tool suffix>.<ext>`, ASCII-safe and unique
/// within a run (`_2`, `_3`… on collisions). The reference app's default is
/// a long templated name with a timestamp and random digits; results here
/// go to the Photos library where the visible name barely matters, so a
/// short predictable name wins.
String outputFileName(String stem, String suffix, String ext, Set<String> taken) {
  var base = stem.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  if (base.isEmpty) base = 'image';
  if (base.length > 60) base = base.substring(0, 60);
  var name = '${base}_$suffix.$ext';
  var i = 2;
  while (taken.contains(name.toLowerCase())) {
    name = '${base}_${suffix}_$i.$ext';
    i++;
  }
  taken.add(name.toLowerCase());
  return name;
}

/// Per-run scratch directory under the OS temp dir. Cleared by [clearAll]
/// on the next launch, so a crash mid-run never leaks files forever.
class WorkDirs {
  WorkDirs._();

  static Directory? _root;

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/picworks');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    return d;
  }

  /// Fresh directory for one run's outputs (or imports).
  static Future<Directory> fresh(String kind) async {
    final r = await root();
    final d = Directory('${r.path}/$kind-${DateTime.now().millisecondsSinceEpoch}');
    await d.create(recursive: true);
    return d;
  }

  /// Delete everything from previous sessions. Best effort.
  static Future<void> clearAll() async {
    try {
      final r = await root();
      await for (final e in r.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('workdir cleanup skipped: $e');
    }
  }
}

/// Where the share sheet should anchor (iPad presents it as a popover and
/// share_plus refuses to open one without an origin rect).
Rect shareOriginOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Outcome of a save-to-Photos attempt, already localised.
class SaveOutcome {
  const SaveOutcome({required this.saved, required this.failed, this.error, this.permanentlyDenied = false});
  final int saved;
  final int failed;

  /// Set when nothing could be saved (permission, disk); null otherwise.
  final String? error;

  /// True when the OS will not show the prompt again — offer "open settings".
  final bool permanentlyDenied;
}

/// Save every successful result to the system Photos library.
///
/// Permission flow (PIPELINE G2): ask → on denial return a visible reason →
/// on permanent denial the caller offers the system settings page.
Future<SaveOutcome> saveResultsToPhotos(List<JobResult> results) async {
  final ok = results.where((r) => r.ok).toList();
  if (ok.isEmpty) return const SaveOutcome(saved: 0, failed: 0);
  try {
    var access = await Gal.hasAccess();
    if (!access) access = await Gal.requestAccess();
    if (!access) {
      return SaveOutcome(
        saved: 0,
        failed: ok.length,
        error: tr(
          zh: '没有相册写入权限,无法保存。你可以在系统设置里允许「添加照片」,或改用「分享」。',
          en: 'Photos permission was denied, so nothing was saved. Allow "Add Photos" in system settings, or use Share instead.',
        ),
        permanentlyDenied: true,
      );
    }
  } on GalException catch (e) {
    return SaveOutcome(saved: 0, failed: ok.length, error: _galMessage(e), permanentlyDenied: e.type == GalExceptionType.accessDenied);
  } catch (e) {
    return SaveOutcome(saved: 0, failed: ok.length, error: '${tr(zh: '无法访问相册', en: 'Could not access Photos')}: $e');
  }

  var saved = 0;
  var failed = 0;
  String? firstError;
  for (final r in ok) {
    try {
      await Gal.putImage(r.outputPath!);
      saved++;
    } on GalException catch (e) {
      failed++;
      firstError ??= _galMessage(e);
      if (e.type == GalExceptionType.accessDenied || e.type == GalExceptionType.notEnoughSpace) {
        failed += ok.length - saved - failed;
        break;
      }
    } catch (e) {
      failed++;
      firstError ??= e.toString();
    }
  }
  return SaveOutcome(saved: saved, failed: failed, error: saved == 0 ? firstError : null);
}

String _galMessage(GalException e) => switch (e.type) {
      GalExceptionType.accessDenied => tr(
          zh: '没有相册写入权限,无法保存。你可以在系统设置里允许「添加照片」,或改用「分享」。',
          en: 'Photos permission was denied. Allow "Add Photos" in system settings, or use Share instead.'),
      GalExceptionType.notEnoughSpace =>
        tr(zh: '设备存储空间不足,无法保存。', en: 'Not enough storage space to save.'),
      GalExceptionType.notSupportedFormat =>
        tr(zh: '系统相册不支持这个格式,请改用「分享」保存到文件。', en: 'The Photos app does not accept this format; use Share to save it as a file.'),
      GalExceptionType.unexpected =>
        '${tr(zh: '保存失败', en: 'Save failed')}: ${e.platformException.message ?? ''}'.trim(),
    };

/// Open the app's page in system settings (permanent permission denial).
Future<void> openSystemSettings() async {
  try {
    await openAppSettings();
  } catch (e) {
    debugPrint('openAppSettings failed: $e');
  }
}

/// Hand the successful outputs to the system share sheet.
Future<String?> shareResults(List<JobResult> results, {Rect? origin}) async {
  final files = [
    for (final r in results)
      if (r.ok) XFile(r.outputPath!),
  ];
  if (files.isEmpty) return tr(zh: '没有可分享的结果', en: 'Nothing to share');
  try {
    await SharePlus.instance.share(ShareParams(files: files, sharePositionOrigin: origin));
    return null;
  } catch (e) {
    return '${tr(zh: '分享失败', en: 'Share failed')}: $e';
  }
}
