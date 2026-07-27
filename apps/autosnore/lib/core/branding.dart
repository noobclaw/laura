import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'AutoSnore';
  static const String appNameZh = '鼾声记录';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — a calm night indigo.
  static const Color seedColor = Color(0xFF5661E0);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '整夜离线记录你的打鼾与夜间响声。声音只在本机分析,不保存任何音频、'
            '无账号、无广告、无网络权限,数据不出手机。这是记录与自我观察工具,'
            '不用于医疗诊断。',
        en: 'Records your snoring and night noises all night, offline. Sound is '
            'analysed on-device — no audio is stored, no account, no ads, no '
            'network permission, nothing leaves your phone. A recording and '
            'self-observation tool, not for medical diagnosis.',
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
