import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here.
abstract final class Branding {
  static const String appNameEn = 'EchoJot';
  static const String appNameZh = '回声笔记';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF00696E); // deep teal

  static String get aboutText => tr(
        zh: '边说边出字的离线语音笔记。转写由系统内置的「设备端语音识别」完成,'
            '不上传、不保存音频文件——无账号、无广告、无网络权限,'
            '你的声音不出这台手机。',
        en: 'Voice notes that become text as you speak. Transcription runs on '
            'the system\'s built-in on-device speech recognizer — nothing is '
            'uploaded and no audio file is kept. No account, no ads, no network '
            'permission: your voice never leaves this phone.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

语音转写使用系统内置的「设备端语音识别」,全程在你的手机上完成。本应用未申请网络权限,不包含任何统计或广告 SDK,不使用任何第三方服务。若系统未提供设备端识别能力,应用会明确提示并停止,绝不改用联网识别。

应用不保存音频文件——语音只在听写过程中经过系统识别器,转成文字后即被丢弃。

你的笔记文字只保存在本机,卸载应用即被移除。你可以随时通过「导出全部笔记」自行备份。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

Speech is transcribed by the system's built-in on-device speech recognizer, on your phone. The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services. If the system offers no on-device recognition, the app says so plainly and stops — it never falls back to online recognition.

No audio file is kept: speech passes through the on-device recognizer while you dictate and is discarded once it becomes text.

Your notes stay on this device and are removed when you uninstall the app. You can back them up any time with "Export all notes".
''',
      );
}
