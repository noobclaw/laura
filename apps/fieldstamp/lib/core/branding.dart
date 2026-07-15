import 'package:flutter/material.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appName = 'FieldStamp';
  static const String version = '1.0.0';

  /// Seed for the Material 3 color scheme (field green).
  static const Color seedColor = Color(0xFF2E7D32);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static const String aboutText =
      'FieldStamp — an offline GPS field-evidence camera. '
      'Every photo is stamped with GPS coordinates, altitude, bearing and time, '
      'burned into the pixels at capture. Export PDF inspection reports or CSV '
      'ledgers. No account, no ads; your photos and coordinates never leave this phone.';

  static const String privacyPolicy = '''
FieldStamp does not collect, store, or transmit any personal data.

The app uses your device camera and location sensors only to create geo-stamped photos on this device. It requests no network permission, contains no analytics or advertising SDKs, and uses no third-party services. Your photos, coordinates, projects, and any exports stay on your device.

Photos and data you create are removed when you uninstall the app. When you choose to share or export a photo, PDF, or CSV, it is handed to whatever app you pick via the system share sheet — FieldStamp itself never uploads anything.
''';
}
