import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `photolift/media` channel: system photo picker in, Photos/MediaStore
/// out. Kotlin (MediaBridge.kt) and Swift (MediaBridge.swift) share the
/// contract; nothing here branches on the platform.
class PickedPhoto {
  const PickedPhoto({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;
}

class MediaException implements Exception {
  const MediaException(this.code, [this.message]);
  /// picker_unavailable | copy_failed | permission_denied | save_failed
  final String code;
  final String? message;
  @override
  String toString() => 'MediaException($code${message == null ? '' : ': $message'})';
}

class MediaBridge {
  MediaBridge._();
  static const MethodChannel _channel = MethodChannel('photolift/media');

  /// Opens the system picker. Null when the user backs out.
  static Future<PickedPhoto?> pick() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('pick');
      if (map == null) return null;
      final path = map['path'] as String?;
      if (path == null) return null;
      return PickedPhoto(
        path: path,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw MediaException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw MediaException('picker_unavailable', e.message);
    }
  }

  /// Copies the JPEG at [path] into the system photo library.
  static Future<void> saveToGallery(String path, {required String displayName}) async {
    try {
      await _channel.invokeMethod<void>('saveToGallery', {
        'path': path,
        'displayName': displayName,
      });
    } on PlatformException catch (e) {
      throw MediaException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw MediaException('save_failed', e.message);
    }
  }

  /// Deep link to this app's page in system Settings (permission recovery).
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (e) {
      debugPrint('openSettings failed: $e');
    }
  }
}
