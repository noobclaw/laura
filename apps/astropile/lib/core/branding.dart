import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'AstroPile';
  static const String appNameZh = '星野叠加';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme: a low-saturation silver grey, so
  /// the scheme stays neutral and the only colour on screen is the star and
  /// the alignment cyan (see tool/app_theme.dart).
  static const Color seedColor = Color(0xFFB4BCCB);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the shell ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '把连拍的夜空照片对齐叠加成一张更干净的照片,并逐帧告诉你对上了没有、对不上是为什么。'
            '全部计算在你的设备上完成,无账号、无广告,照片不出手机。\n\n'
            '开源致谢:星阵配准算法参考 astroalign(MIT,© 2016 Martin Beroiz)的公开设计思路,'
            '本应用为独立的 Dart 实现,未复制其代码。',
        en: 'Aligns a burst of night-sky photos and stacks them into one '
            'cleaner picture, telling you frame by frame whether it lined up '
            'and why it did not. Everything runs on your device — no account, '
            'no ads, no photo ever leaves the phone.\n\n'
            'Credits: the asterism-matching approach follows the published '
            'design of astroalign (MIT, © 2016 Martin Beroiz). This app is an '
            'independent Dart implementation and copies none of its code.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有处理均在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你选择的照片只在本机读取与处理;叠加过程中的临时文件保存在应用的私有缓存目录,任务结束或下次启动时自动删除。成片只有在你主动点击「保存到相册」或「分享」时才离开本应用。

你在应用内创建的数据仅保存在你的设备上,卸载应用即被删除。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

The photos you pick are read and processed on this device only. Intermediate files live in the app's private cache directory and are deleted when the run finishes or on the next launch. The finished picture leaves the app only when you tap Save to Photos or Share.

Data you create in the app stays on your device and is removed when you uninstall the app.
''',
      );
}
