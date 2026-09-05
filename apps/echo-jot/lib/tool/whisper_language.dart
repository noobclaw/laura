// Pure mapping from the app's dictation language tags to whisper.cpp
// language codes. No Flutter imports so it is unit-testable in isolation.

/// Language codes whisper.cpp accepts (`whisper_lang_id`). Anything outside
/// this set is handed to the model as `auto` rather than rejected — the model
/// then detects the language itself, which beats a hard error for a tag we
/// simply did not list.
const Set<String> whisperLanguageCodes = {
  'en', 'zh', 'de', 'es', 'ru', 'ko', 'fr', 'ja', 'pt', 'tr', 'pl', 'ca', //
  'nl', 'ar', 'sv', 'it', 'id', 'hi', 'fi', 'vi', 'he', 'uk', 'el', 'ms', //
  'cs', 'ro', 'da', 'hu', 'ta', 'no', 'th', 'ur', 'hr', 'bg', 'lt', 'la', //
  'mi', 'ml', 'cy', 'sk', 'te', 'fa', 'lv', 'bn', 'sr', 'az', 'sl', 'kn', //
  'et', 'mk', 'br', 'eu', 'is', 'hy', 'ne', 'mn', 'bs', 'kk', 'sq', 'sw', //
  'gl', 'mr', 'pa', 'si', 'km', 'sn', 'yo', 'so', 'af', 'oc', 'ka', 'be', //
  'tg', 'sd', 'gu', 'am', 'yi', 'lo', 'uz', 'fo', 'ht', 'ps', 'tk', 'nn', //
  'mt', 'sa', 'lb', 'my', 'bo', 'tl', 'mg', 'as', 'tt', 'haw', 'ln', 'ha', //
  'ba', 'jw', 'su', 'yue',
};

/// The value handed to whisper for "let the model decide".
const String whisperAutoLanguage = 'auto';

/// "zh-CN" → "zh", "en-US" → "en", "auto"/"" → "auto". A tag whose primary
/// subtag whisper does not know also becomes "auto" (see
/// [whisperLanguageCodes]). Legacy underscore tags ("zh_CN") are tolerated.
String whisperLanguageCode(String tag) {
  final t = tag.trim().toLowerCase();
  if (t.isEmpty || t == whisperAutoLanguage) return whisperAutoLanguage;
  // Old-style "iw" (Hebrew) / "in" (Indonesian) tags still appear on some
  // Android builds; whisper uses the modern codes.
  final primary = switch (t.split(RegExp('[-_]')).first) {
    'iw' => 'he',
    'in' => 'id',
    final p => p,
  };
  return whisperLanguageCodes.contains(primary) ? primary : whisperAutoLanguage;
}

/// Whisper writes Chinese in whichever script its decoding drifts toward. An
/// initial prompt in the wanted script steers it: simplified for zh-CN (and
/// any bare "zh"), traditional for zh-TW / zh-HK / zh-Hant. Other languages
/// get no prompt — an unrelated prompt would only bias vocabulary.
String? whisperInitialPrompt(String tag) {
  final t = tag.trim().toLowerCase();
  if (!t.startsWith('zh')) return null;
  final traditional = t.contains('tw') ||
      t.contains('hk') ||
      t.contains('mo') ||
      t.contains('hant');
  return traditional ? '以下是繁體中文的句子。' : '以下是普通话的句子。';
}
