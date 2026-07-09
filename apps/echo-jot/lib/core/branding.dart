import 'package:flutter/material.dart';

/// All per-app identity lives here.
abstract final class Branding {
  static const String appName = '回声笔记';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF00696E); // deep teal

  static const String aboutText =
      '按住说话、松手变文字的离线语音笔记。'
      '无账号、无广告、无网络权限——你的声音不出这台手机。';

  static const String privacyPolicy = '''
回声笔记不收集、不存储、不传输任何个人数据。

所有录音与转写都在你的设备本地完成。本应用未申请网络权限,不包含任何统计或广告 SDK,不使用任何第三方服务。

你在应用内创建的全部数据只保存在本机,卸载应用即被移除。你可以随时通过「导出全部笔记」自行备份。

This app does not collect, store, or transmit any personal data. All recording and transcription happen locally on your device. The app does not request network access and contains no analytics or advertising SDKs.
''';
}
