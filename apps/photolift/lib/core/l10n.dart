import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'json_file_store.dart';

/// Minimal, factory-friendly localization (PIPELINE.md rule: every app ships
/// multilingual — zh + en mandatory, ja/others per market fit).
///
/// Every user-visible string is declared inline at its use site:
///
///     Text(tr(zh: '新建', en: 'New'))
///
/// No codegen, no key files, English fallback. The language follows the
/// system unless the user picks one in Settings ([AppLanguage]).
/// `required` parameters make the analyzer enforce that zh and en both exist.
/// Do NOT wrap logs, JSON keys, or file names — user-visible text only.
String tr({
  required String zh,
  required String en,
  String? zht,
  String? ja,
  String? es,
  String? pt,
  String? de,
  String? fr,
}) {
  switch (AppLanguage.effectiveCode) {
    case 'zh':
      return zh;
    case 'zht':
      return zht ?? zh;
    case 'ja':
      return ja ?? en;
    case 'es':
      return es ?? en;
    case 'pt':
      return pt ?? en;
    case 'de':
      return de ?? en;
    case 'fr':
      return fr ?? en;
    default:
      return en;
  }
}

/// True when the effective language is Chinese — for occasional per-locale
/// layout/format decisions beyond plain strings.
bool get isZhLocale {
  final c = AppLanguage.effectiveCode;
  return c == 'zh' || c == 'zht';
}

/// The user's language choice, persisted on device. `null` = follow the
/// system (the default). Changing it rebuilds the whole app (see main.dart),
/// so every `tr()` call and every Material widget picks it up at once.
///
/// Added 2026-09-02 on the user's request: a Chinese owner testing an
/// English-system iPhone (and vice versa) needs to flip the language
/// without changing the phone.
class AppLanguage {
  AppLanguage._();

  /// Choices offered in Settings. Only languages every string of the app
  /// actually has: offering `ja` here while the tool passes no `ja:` strings
  /// gave the user a "日本語" option that turned the app English (2026-09-04
  /// audit). Add `ja` back per app only once its strings carry `ja:`.
  static const List<String> choices = [
    'en', 'zh', 'zht', 'ja', 'es', 'pt', 'de', 'fr',
  ];

  static final ValueNotifier<String?> override = ValueNotifier<String?>(null);
  static final JsonFileStore _file = JsonFileStore('language.json');
  static bool _loaded = false;

  /// Read the saved choice. Call once before `runApp`; safe to call again.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _file.read();
      final code = raw?['code'];
      if (code is String && choices.contains(code)) override.value = code;
    } catch (e) {
      debugPrint('language load skipped: $e');
    }
  }

  static Future<void> set(String? code) async {
    override.value = code;
    _file.write({'code': code});
  }

  /// The Locale to hand MaterialApp, or null to follow the system.
  static Locale? get locale => switch (override.value) {
        null => null,
        'zht' => const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant'),
        final c => Locale(c),
      };

  static String get effectiveCode =>
      override.value ?? _systemCode(PlatformDispatcher.instance.locale);

  /// Map the device locale onto one of [choices]. Traditional Chinese is
  /// told apart by script (zh-Hant) or by region (TW/HK/MO) because iOS
  /// reports either form depending on the user's settings.
  static String _systemCode(Locale l) {
    final lang = l.languageCode.toLowerCase();
    if (lang == 'zh') {
      final script = l.scriptCode?.toLowerCase();
      final region = l.countryCode?.toUpperCase();
      if (script == 'hant' ||
          region == 'TW' ||
          region == 'HK' ||
          region == 'MO') {
        return 'zht';
      }
      return 'zh';
    }
    return lang;
  }

  static String label(String? code) => switch (code) {
        'zh' => '简体中文',
        'zht' => '繁體中文',
        'en' => 'English',
        'ja' => '日本語',
        'es' => 'Español',
        'pt' => 'Português',
        'de' => 'Deutsch',
        'fr' => 'Français',
        _ => tr(zh: '跟随系统', en: 'Follow system', zht: '跟隨系統', ja: 'システムに従う', es: 'Seguir al sistema', pt: 'Seguir o sistema', de: 'Systemsprache', fr: 'Suivre le système'),
      };
}
