import 'package:flutter/material.dart';
import 'words.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
///
/// i18n: the script seeds the same display name into both languages — set the
/// proper per-locale names by hand (store/listing.md has both). Same for the
/// android side: android/app/src/main/res/values{,-zh}/strings.xml.
abstract final class OhmIdentity {
  static const String appNameEn = 'OhmBench';
  static const String appNameZh = '电路台';
  static String get appName => tr(zh: appNameZh, en: appNameEn);

  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme: hue 52, the warm yellow of the
  /// moving charge on the bench. The first plan used hue 198 (scope cyan),
  /// but draftbook already ships at 198 — PIPELINE rule 13 forbids sharing a
  /// ±20° band, so the chrome took the free yellow band (50–65) and cyan
  /// stayed on the canvas only, as the colour of positive voltage.
  static const Color seedColor = Color(0xFFDCC21C);

  /// Settings > Privacy policy. Written about this app, not a template:
  /// what OhmBench stores, where, and what it never does.
  static String get privacyPolicy => tr(
        zh: '''
电路台只做一件事:在你的手机上算电路。

你画的电路保存在本机的一个文件里(ohmbench_projects.json),每次改动都会写入;Pro 的解锁状态单独存一份。卸载应用,这两份文件随之删除。

求解器、示波器和动画全部在手机上运行,应用不建立任何网络连接,不带统计、广告或崩溃上报 SDK,也不需要账号。

购买 Pro 由 App Store / Google Play 处理,我们拿不到你的支付信息;重装后在设置里「恢复购买」即可找回。

有问题请写信:bitcexgroup@gmail.com
''',
        en: '''
OhmBench does one thing: it solves circuits on your phone.

The circuits you draw are kept in one file on this device (ohmbench_projects.json), written on every change; the Pro unlock is stored separately. Uninstalling the app deletes both.

The solver, the scope and the animation all run on the phone. The app makes no network connections and contains no analytics, advertising or crash-reporting SDKs, and there is no account.

Buying Pro is handled by the App Store / Google Play; we never see your payment details. After a reinstall, "Restore purchase" in settings brings Pro back.

Questions: bitcexgroup@gmail.com
''',
      );
}
