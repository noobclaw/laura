import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: per-locale display names come from store/listing.md. Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'DayCount';
  static const String appNameZh = '倒数日';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — a warm coral that reads well both
  /// in the app and on the home-screen widget background.
  static const Color seedColor = Color(0xFFE7625F);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '倒数日 — 记录每个重要日子的倒计时与纪念日，全部在本机运行。'
            '桌面小组件一眼看到最近的日子。无账号、无广告、不联网。',
        en: 'DayCount — countdowns and days-since for every date that matters, '
            'all on your device. See the nearest day at a glance on the '
            'home-screen widget. No account, no ads, no network.',
      );

  static String get privacyPolicy => tr(
        zh: '''
倒数日不收集、不存储、也不传输任何个人数据。

所有事件与设置都只保存在你的设备本地。App 不申请网络访问权限，不含任何统计或广告 SDK，也不使用任何第三方服务。

你创建的日子只存在这台设备上，卸载 App 即随之删除。
''',
        en: '''
DayCount does not collect, store, or transmit any personal data.

All events and settings stay on your device. The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services.

The days you create live only on this device and are removed when you uninstall the app.
''',
      );
}
