import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = '倒数日';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — a warm coral that reads well both
  /// in the app and on the home-screen widget background.
  static const Color seedColor = Color(0xFFE7625F);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static const String aboutText =
      '倒数日 — 记录每个重要日子的倒计时与纪念日，全部在本机运行。'
      '桌面小组件一眼看到最近的日子。无账号、无广告、不联网。';

  static const String privacyPolicy = '''
倒数日不收集、不存储、也不传输任何个人数据。

所有事件与设置都只保存在你的设备本地。App 不申请网络访问权限，不含任何统计或广告 SDK，也不使用任何第三方服务。

你创建的日子只存在这台设备上，卸载 App 即随之删除。

——

DayCount does not collect, store, or transmit any personal data.

All events and settings stay on your device. The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services. Your data lives only on this device and is removed when you uninstall the app.
''';
}
