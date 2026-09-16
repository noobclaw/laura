import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  /// Launcher name (English default, per PIPELINE 视觉标准 11). The Chinese
  /// name is carried by android res/values-zh/strings.xml and
  /// ios/Runner/zh-Hans.lproj/InfoPlist.strings — keep all three in sync.
  static const String appNameEn = 'Draftbook';
  static const String appNameZh = 'Draftbook 写长篇';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — ink blue, hue 198°.
  /// (PIPELINE 视觉标准 13 色相分配表: 190–210° was the open band; the nearest
  /// neighbours are remcard 174° and orbit 223°, both more than 20° away.)
  static const Color seedColor = Color(0xFF0A6C96);

  static String get aboutText => tr(
        zh: '为长篇写作做的组织工具:一本书拆成章与场景,随手写、随手重排。'
            '全部在你的手机上完成 —— 无账号、无广告、不联网,稿子不出手机。',
        en: 'An organiser for long-form writing: a book split into chapters and '
            'scenes, written and reordered as you go. Everything happens on '
            'your phone — no account, no ads, no network. Your draft never '
            'leaves the device.',
      );

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

你的项目、章节、场景正文与版本历史全部保存在本机的应用沙盒里。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

只有你主动点击「导出 / 分享」时,稿件才会交给你自己选择的那个应用(邮件、文件、云盘……),去向完全由你决定。

卸载应用会一并删除这些数据,所以重要的稿子请定期导出备份。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

Your projects, chapters, scene text and version history are kept in the app's own storage on this device. The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services.

Your manuscript only ever leaves the app when you tap Export / Share yourself, and then only to the app you pick (mail, Files, a cloud drive…).

Uninstalling the app deletes this data with it, so export a backup of anything you care about.
''',
      );
}
