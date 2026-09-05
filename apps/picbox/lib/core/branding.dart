import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'PicWorks';
  static const String appNameZh = '图片万能箱';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme: a deep teal — "darkroom" tools,
  /// not a social photo app.
  static const Color seedColor = Color(0xFF0F8B8D);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission. The second paragraph is
  /// the Apache-2.0 attribution for the reference implementation whose
  /// processing rules (size search, resize anchors, metadata handling) were
  /// studied and re-implemented in Dart.
  static String get aboutText => tr(
        zh: '一站式离线图片工具箱:压缩、缩放、格式转换、裁剪旋转、去除元数据、加水印,支持批量处理。'
            '全部在你的设备上完成,无账号、无广告,图片不出手机。\n\n'
            '处理逻辑参考了开源项目 ImageToolbox(T8RIN,Apache License 2.0,'
            'https://github.com/T8RIN/ImageToolbox),已用 Dart 重新实现;'
            '未复制其代码与资源。感谢原作者。',
        en: 'A one-stop offline image toolbox: compress, resize, convert, crop & rotate, '
            'strip metadata and watermark — in batches. Everything runs on your device: '
            'no account, no ads, no picture ever leaves the phone.\n\n'
            'Processing rules were studied from the open-source ImageToolbox project '
            '(T8RIN, Apache License 2.0, https://github.com/T8RIN/ImageToolbox) and '
            're-implemented in Dart; no code or assets were copied. Thanks to the author.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有图片处理均在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你选择的图片只在处理期间以临时文件形式存在于应用沙盒中;处理结果只有在你点击「保存到相册」或「分享」时才会离开应用沙盒,去向由你决定。应用内的设置与水印预设仅保存在你的设备上,卸载应用即被删除。

「去元数据」工具会读取图片内嵌的 EXIF/GPS 等信息并展示给你,这些信息不会被上传或用于任何其他用途。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All image processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Pictures you pick exist only as temporary files inside the app sandbox while they are processed; results leave the sandbox only when you tap "Save to Photos" or "Share", and only where you send them. Settings and watermark presets are stored on your device and removed when you uninstall the app.

The metadata tool reads the EXIF/GPS data embedded in a picture to show it to you; that data is never uploaded or used for any other purpose.
''',
      );
}
