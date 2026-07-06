import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = 'Tool Shell';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF3F51B5);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the shell ships without the INTERNET permission.
  static const String aboutText =
      'A small, focused tool that runs entirely on your device. '
      'No account, no ads, no data leaves your phone.';

  static const String privacyPolicy = '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Data you create in the app stays on your device and is removed when you uninstall the app.
''';
}
