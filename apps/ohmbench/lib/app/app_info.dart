import 'dart:io' show Platform;

import '../i18n/txt.dart';

/// Name, version and the privacy text shown in Settings.
abstract final class AppInfo {
  static String get name => Txt.ohmbench;

  static const String version = '1.1.0';

  static bool get _apple => Platform.isIOS || Platform.isMacOS;

  static String get privacyPolicy => _apple
      ? Txt.ohmbenchDoesOneThing
      : Txt.ohmbenchDoesOneThing2;
}
