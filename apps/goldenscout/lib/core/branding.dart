import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = 'GoldenScout';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme — golden-hour amber.
  static const Color seedColor = Color(0xFFF5A623);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static const String aboutText =
      'GoldenScout plans your light — sunrise, sunset, golden hour, blue hour '
      'and the sun & moon\'s compass bearings — entirely on your device. '
      'The sun/moon almanac is deterministic astronomy math; GPS and the '
      'compass are local sensors. No account, no ads, no network. Times are '
      'shown in your device\'s timezone.';

  static const String privacyPolicy = '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Data you create in the app stays on your device and is removed when you uninstall the app.
''';
}
