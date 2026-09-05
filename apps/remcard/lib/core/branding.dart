import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'Remcard';
  static const String appNameZh = '记得';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.2.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF00897B); // teal — calm, study-friendly

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '记得(Remcard)— 纯离线的间隔重复记忆卡。'
            '建牌组、按 FSRS 算法复习,把知识记得更牢。'
            '无账号、无广告、无订阅,你的卡片永远不出这台手机。',
        en: 'Remcard — offline spaced-repetition flashcards. '
            'Build decks, review on the FSRS schedule, and remember more. '
            'No account, no ads, no subscription; your cards never leave this phone.',
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
