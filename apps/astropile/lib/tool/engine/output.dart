import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';

/// Per-run scratch directory. A 32-frame full-resolution run writes about a
/// gigabyte of aligned frames here, so it is cleared on the next launch as
/// well as at the end of every run — a force-quit must not leave that behind.
class WorkDirs {
  WorkDirs._();

  static Directory? _root;

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/astropile');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    return d;
  }

  static int _seq = 0;

  /// A directory nothing else is using. The counter matters: two runs
  /// started in the same millisecond would otherwise share a directory and
  /// overwrite each other's aligned frames.
  static Future<Directory> fresh(String kind) async {
    final r = await root();
    final d = Directory(
        '${r.path}/$kind-${DateTime.now().millisecondsSinceEpoch}-${_seq++}');
    await d.create(recursive: true);
    return d;
  }

  /// Best-effort delete of everything from previous sessions.
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

  /// Total bytes currently held in the scratch tree.
  static Future<int> usedBytes() async {
    var total = 0;
    try {
      final r = await root();
      await for (final e in r.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('workdir size skipped: $e');
    }
    return total;
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
  const SaveOutcome({required this.saved, this.error, this.permanentlyDenied = false});
  final bool saved;

  /// Set when the save failed; null on success.
  final String? error;

  /// True when the OS will not show the prompt again — offer "open settings".
  final bool permanentlyDenied;
}

/// Save one finished image to the system Photos library.
///
/// Permission flow (PIPELINE G2): ask → on denial return a visible reason →
/// on permanent denial the caller offers the system settings page.
Future<SaveOutcome> saveToPhotos(String path) async {
  try {
    var access = await Gal.hasAccess();
    if (!access) access = await Gal.requestAccess();
    if (!access) {
      return SaveOutcome(
        saved: false,
        error: tr(
          zh: '没有相册写入权限,无法保存。你可以在系统设置里允许「添加照片」,或改用「分享」。',
          en: 'Photos permission was denied, so nothing was saved. Allow "Add Photos" in system settings, or use Share instead.',
        ),
        permanentlyDenied: true,
      );
    }
  } on GalException catch (e) {
    return SaveOutcome(
        saved: false,
        error: _galMessage(e),
        permanentlyDenied: e.type == GalExceptionType.accessDenied);
  } catch (e) {
    return SaveOutcome(
        saved: false, error: '${tr(zh: '无法访问相册', en: 'Could not access Photos')}: $e');
  }

  try {
    await Gal.putImage(path);
    return const SaveOutcome(saved: true);
  } on GalException catch (e) {
    return SaveOutcome(
        saved: false,
        error: _galMessage(e),
        permanentlyDenied: e.type == GalExceptionType.accessDenied);
  } catch (e) {
    return SaveOutcome(saved: false, error: '${tr(zh: '保存失败', en: 'Save failed')}: $e');
  }
}

String _galMessage(GalException e) => switch (e.type) {
      GalExceptionType.accessDenied => tr(
          zh: '没有相册写入权限,无法保存。你可以在系统设置里允许「添加照片」,或改用「分享」。',
          en: 'Photos permission was denied. Allow "Add Photos" in system settings, or use Share instead.'),
      GalExceptionType.notEnoughSpace =>
        tr(zh: '设备存储空间不足,无法保存。', en: 'Not enough storage space to save.'),
      GalExceptionType.notSupportedFormat => tr(
          zh: '系统相册不支持这个格式,请改用「分享」保存到文件。',
          en: 'The Photos app does not accept this format; use Share to save it as a file.'),
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

/// Hand the finished image to the system share sheet.
Future<String?> shareFile(String path, {Rect? origin}) async {
  try {
    await SharePlus.instance
        .share(ShareParams(files: [XFile(path)], sharePositionOrigin: origin));
    return null;
  } catch (e) {
    return '${tr(zh: '分享失败', en: 'Share failed')}: $e';
  }
}
