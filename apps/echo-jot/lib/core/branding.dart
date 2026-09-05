import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here.
abstract final class Branding {
  static const String appNameEn = 'EchoJot';
  static const String appNameZh = '回声笔记';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.2.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF00696E); // deep teal

  static String get aboutText => tr(
        zh: '离线语音笔记。转写在这台手机上完成:用系统内置的「设备端语音识别」(边说边出字),'
            '或应用自带的 Whisper 模型(停止后转写)。不上传、不保存音频文件——'
            '无账号、无广告、无网络权限,你的声音不出这台手机。\n\n'
            '内含开源组件:whisper.cpp(MIT)、FFmpeg(LGPL v3)。',
        en: 'Offline voice notes. Transcription happens on this phone: either '
            'the system\'s built-in on-device speech recognizer (text as you '
            'speak) or the app\'s bundled Whisper model (after you stop). '
            'Nothing is uploaded and no audio file is kept. No account, no ads, '
            'no network permission: your voice never leaves this phone.\n\n'
            'Includes open-source components: whisper.cpp (MIT), FFmpeg (LGPL v3).',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

语音转写全程在你的手机上完成,有两种引擎可选:
• 系统识别:使用系统内置的「设备端语音识别」,边说边出字,不写入任何音频。
• Whisper 离线:使用随应用打包的 Whisper 语音模型(约 57 MB,安装时已包含,不会下载)。录音以临时文件形式保存在应用私有目录,转写完成后立即删除。

本应用未申请网络权限,不包含任何统计或广告 SDK,不使用任何第三方服务;两种引擎都不联网。若系统未提供设备端识别能力,应用会明确提示并停止,或由你改用 Whisper 离线引擎,绝不改用联网识别。

除上述临时录音外,应用不保存音频文件。

你的笔记文字只保存在本机,卸载应用即被移除。你可以随时通过「导出全部笔记」自行备份。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

Speech is transcribed entirely on your phone, by one of two engines you choose:
• System recognizer: the system's built-in on-device speech recognition; text appears as you speak and no audio is written.
• Whisper offline: a Whisper speech model bundled inside the app (about 57 MB, included at install time, never downloaded). The recording is held as a temporary file in the app's private directory and deleted as soon as it has been transcribed.

The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services; neither engine goes online. If the system offers no on-device recognition, the app says so plainly and stops, or you switch to the Whisper offline engine — it never falls back to online recognition.

Apart from that temporary recording, no audio file is kept.

Your notes stay on this device and are removed when you uninstall the app. You can back them up any time with "Export all notes".
''',
      );
}
