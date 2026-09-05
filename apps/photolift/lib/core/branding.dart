import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appNameEn = 'PhotoLift';
  // "老照片修复" alone is shared by dozens of store listings; the "离线"
  // qualifier is the product wedge and keeps the name distinct.
  static const String appNameZh = '离线老照片修复';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme: a deep violet — the "sparkle"
  /// family, distinct from the sepia of the photos it restores.
  static const Color seedColor = Color(0xFF6C4DFF);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '把模糊的老照片放大、修清晰。AI 模型(Real-ESRGAN)完全在你的手机上运行,'
            '照片从不上传。无账号、无广告、一次买断。',
        en: 'Upscale and sharpen old, blurry photos. The AI model (Real-ESRGAN) '
            'runs entirely on your phone — photos are never uploaded. '
            'No account, no ads, one-time purchase.',
      );

  /// The store this binary is sold through - App Review reads a mention of
  /// the other platform in an iOS build as guideline 2.3.10.
  static String get _storeName =>
      Platform.isIOS || Platform.isMacOS ? 'App Store' : 'Google Play';

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有照片处理(放大、降噪)都由内置的 AI 模型在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你选择的照片和修复后的结果只保存在本应用的私有目录中;只有当你点击「保存到相册」时,结果才会写入系统相册。卸载应用即删除应用内的全部数据。

内购通过 $_storeName 完成,应用本身不会接触你的支付信息。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All photo processing (upscaling, denoising) is done by the bundled AI model locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Photos you pick and their enhanced results are kept only in the app's private folder; a result is written to your system photo library only when you tap "Save to Photos". Uninstalling the app removes all of its data.

In-app purchases go through $_storeName; the app itself never sees your payment details.
''',
      );
}
