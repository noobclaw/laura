import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = '干净闹钟';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme. A calm teal — fresh and quiet.
  static const Color seedColor = Color(0xFF00897B);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static const String aboutText =
      'A clean alarm clock that runs entirely on your device. '
      'No account, no ads, no analytics, and no network access. '
      'Your alarms never leave your phone.';

  static const String privacyPolicy = '''
干净闹钟 does not collect, store, or transmit any personal data.

All alarms and settings are stored locally on your device. The app does not request network access, contains no analytics or advertising SDKs, and uses no third-party services.

To ring on time the app requests notification, exact-alarm, and full-screen-intent permissions — these are used only to display and sound your alarms on this device. Uninstalling the app removes all of your data.
''';
}
