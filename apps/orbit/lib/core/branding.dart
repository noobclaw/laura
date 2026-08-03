import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class Branding {
  static const String appNameEn = 'Orbit';
  static const String appNameZh = '卫星过境';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — the blue of a deep, clear night.
  static const Color seedColor = Color(0xFF2F6BFF);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: 'Orbit 告诉你头顶那颗人造卫星几点几分、从哪个方位过境。轨道推演(SGP4)、日照判定、方位对齐全部在你的手机上算完——不申请网络权限,没有账号,没有广告。\n\n'
            '应用内置一份公开的轨道根数快照,你也可以随时粘贴导入更新的数据。',
        en: 'Orbit tells you when the satellite overhead passes, and which way to look. Orbital propagation (SGP4), sunlight geometry and compass alignment all run on your phone — no network permission, no account, no ads.\n\n'
            'A public snapshot of orbital elements ships with the app, and you can paste in fresher data any time.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有处理均在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

定位权限是可选的,只用于取一次坐标来计算过境时刻,坐标只保存在本机;你也可以完全不给权限,手动输入经纬度。

你在应用内创建的数据仅保存在你的设备上,卸载应用即被删除。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Location permission is optional and used only to take a single fix for computing pass times. Coordinates stay on this device, and you can skip the permission entirely and type coordinates instead.

Data you create in the app stays on your device and is removed when you uninstall the app.
''',
      );
}
