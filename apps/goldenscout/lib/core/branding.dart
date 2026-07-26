import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'GoldenScout';
  // Store listing zh title is "GoldenScout 天光规划器"; the short form keeps
  // the launcher/app-bar label readable.
  static const String appNameZh = '天光规划器';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — golden-hour amber.
  static const Color seedColor = Color(0xFFF5A623);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: 'GoldenScout 完全在你的设备上规划光线——日出日落、黄金时段、蓝调时刻,'
            '以及太阳与月亮的罗盘方位。日月历法是确定性的天文数学;GPS 与罗盘是'
            '本机传感器。无账号、无广告、零联网。时间按你设备所在时区显示。',
        en: 'GoldenScout plans your light — sunrise, sunset, golden hour, blue hour '
            'and the sun & moon\'s compass bearings — entirely on your device. '
            'The sun/moon almanac is deterministic astronomy math; GPS and the '
            'compass are local sensors. No account, no ads, no network. Times are '
            'shown in your device\'s timezone.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有处理均在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你在应用内创建的数据仅保存在你的设备上,卸载应用即被删除。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Data you create in the app stays on your device and is removed when you uninstall the app.
''',
      );
}
