import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../platform/disk_slot.dart';

/// Which language OhmBench speaks.
///
/// English and Simplified Chinese are complete; anything else falls back
/// to English. The user's pick (Settings › Language) wins over the phone's
/// list of preferred languages and is kept in `language.json`.
abstract final class Lang {
  /// Languages that have every string in `catalog.dart`.
  static const List<String> supported = ['en', 'zh'];

  /// The explicit pick, or null to follow the phone.
  static final ValueNotifier<String?> picked = ValueNotifier<String?>(null);

  static final DiskSlot _slot = DiskSlot('language.json');
  static Future<void>? _restoring;

  static Future<void> restore() => _restoring ??= () async {
        final doc = await _slot.load();
        final code = doc?['lang'];
        if (code is String && supported.contains(code)) picked.value = code;
      }();

  static void pick(String? code) {
    picked.value = code;
    _slot.put({'lang': code});
  }

  /// The language in effect right now.
  static String get current {
    final p = picked.value;
    if (p != null) return p;
    for (final l in PlatformDispatcher.instance.locales) {
      final c = l.languageCode.toLowerCase();
      if (supported.contains(c)) return c;
    }
    return 'en';
  }

  static bool get isChinese => current == 'zh';

  /// For MaterialApp: null lets Flutter follow the phone.
  static Locale? get materialLocale {
    final p = picked.value;
    return p == null ? null : Locale(p);
  }

  /// Native name of a language, for the picker.
  static String nativeName(String code) => switch (code) {
        'zh' => '简体中文',
        _ => 'English',
      };
}

/// For text that arrives as data with both languages attached (the example
/// circuits), not for interface strings — those live in `catalog.dart`.
String bilingual({required String en, required String zh}) =>
    Lang.isChinese ? zh : en;
