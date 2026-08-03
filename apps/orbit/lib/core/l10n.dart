import 'dart:ui';

/// Minimal, factory-friendly localization (PIPELINE.md rule: every app ships
/// multilingual — zh + en mandatory, ja/others per market fit).
///
/// Every user-visible string is declared inline at its use site:
///
///     Text(tr(zh: '新建', en: 'New'))
///
/// No codegen, no key files, English fallback, follows the system locale.
/// `required` parameters make the analyzer enforce that zh and en both exist.
/// Do NOT wrap logs, JSON keys, or file names — user-visible text only.
String tr({required String zh, required String en, String? ja}) {
  final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  if (code == 'zh') return zh;
  if (code == 'ja' && ja != null) return ja;
  return en;
}

/// True when the device language is Chinese — for occasional per-locale
/// layout/format decisions beyond plain strings.
bool get isZhLocale =>
    PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'zh';
