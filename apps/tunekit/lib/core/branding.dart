import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'TuneBench';
  static const String appNameZh = '调音节拍器';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF5B5BD6);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the shell ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '调音器、节拍器与和弦音阶练习,全部在你的手机上完成。麦克风只在调音和练习时用来测音高,声音不保存、不上传;无账号、无广告。',
        en: 'Tuner, metronome and chord/scale practice, all on your phone. '
            'The microphone is used only to measure pitch while you tune or practise; '
            'audio is never stored or uploaded. No account, no ads.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

麦克风:调音器与「弹奏检查」功能需要使用麦克风来实时测量音高。音频只在内存中做即时分析,不会录制、保存或上传;离开调音页面或应用切到后台时,麦克风立即关闭。

所有处理均在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你的练习记录仅保存在你的设备上,卸载应用即被删除。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

Microphone: the tuner and the "play and check" feature use the microphone to measure pitch in real time. Audio is analysed in memory only — it is never recorded, saved or uploaded — and the microphone is switched off as soon as you leave the tuner or the app goes to the background.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Your practice log stays on your device and is removed when you uninstall the app.
''',
      );
}
