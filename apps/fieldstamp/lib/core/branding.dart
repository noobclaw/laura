import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'FieldStamp';
  static const String appNameZh = 'FieldStamp';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme (field green).
  static const Color seedColor = Color(0xFF2E7D32);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: 'FieldStamp(现场印记)— 纯离线的 GPS 现场取证相机。'
            '每张照片都会在拍摄瞬间把 GPS 坐标、海拔、方位和时间直接烧入像素。'
            '可导出 PDF 巡检报告或 CSV 台账。无账号、无广告;'
            '你的照片和坐标永远不会离开这台手机。',
        en: 'FieldStamp — an offline GPS field-evidence camera. '
            'Every photo is stamped with GPS coordinates, altitude, bearing and time, '
            'burned into the pixels at capture. Export PDF inspection reports or CSV '
            'ledgers. No account, no ads; your photos and coordinates never leave this phone.',
      );

  static String get privacyPolicy => tr(
        zh: '''
FieldStamp(现场印记)不收集、不存储、不传输任何个人数据。

应用仅使用你设备上的相机和定位传感器,在本机生成带地理水印的照片。它不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。你的照片、坐标、项目以及所有导出文件都只保存在你的设备上。

你在应用内创建的照片和数据会在卸载应用时一并删除。当你主动分享或导出照片、PDF 或 CSV 时,文件会通过系统分享面板交给你选择的应用——FieldStamp 本身从不上传任何内容。
''',
        en: '''
FieldStamp does not collect, store, or transmit any personal data.

The app uses your device camera and location sensors only to create geo-stamped photos on this device. It requests no network permission, contains no analytics or advertising SDKs, and uses no third-party services. Your photos, coordinates, projects, and any exports stay on your device.

Photos and data you create are removed when you uninstall the app. When you choose to share or export a photo, PDF, or CSV, it is handed to whatever app you pick via the system share sheet — FieldStamp itself never uploads anything.
''',
      );
}
