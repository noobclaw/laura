import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = 'Remcard';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme.
  static const Color seedColor = Color(0xFF00897B); // teal — calm, study-friendly

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static const String aboutText =
      'Remcard — offline spaced-repetition flashcards. '
      'Build decks, review with the SM-2 schedule, and remember more. '
      'No account, no ads, no subscription; your cards never leave this phone.';

  static const String privacyPolicy = '''
This app does not collect, store, or transmit any personal data.

All processing happens locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Data you create in the app stays on your device and is removed when you uninstall the app.
''';
}
