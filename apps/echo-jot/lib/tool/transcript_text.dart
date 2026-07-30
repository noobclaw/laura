// Pure text rules that turn the recognizer's raw output into a readable note.
//
// The system on-device recognizer hands back one unpunctuated chunk per
// utterance ("买牛奶和鸡蛋" / "remember to call the dentist"), with no trailing
// period and no capital letter. Whisper used to do that for us; now we do it
// locally with plain string rules — no model, no network, and unit-testable.

/// True when [text] contains CJK characters, i.e. a script that needs no spaces
/// between segments and uses full-width punctuation.
bool isCjkText(String text) {
  for (final rune in text.runes) {
    // CJK unified ideographs + common extensions, plus kana and Hangul.
    if ((rune >= 0x3040 && rune <= 0x30FF) || // kana
        (rune >= 0x3400 && rune <= 0x4DBF) || // CJK ext A
        (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified
        (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul
        (rune >= 0xF900 && rune <= 0xFAFF)) {
      return true;
    }
  }
  return false;
}

const _sentenceEnders = '。！？!?.…~';
const _anyTerminal = '。！？!?.…,,、;;::~';

/// Appends one finalised utterance to the note text, adding the punctuation and
/// spacing the recognizer omits.
///
/// - CJK: previous segment gets a full-width 。 and the new one is appended with
///   no space.
/// - Latin: previous segment gets a period, the new one starts capitalised and
///   is separated by a space.
/// Existing punctuation is respected — the user may have edited the text by hand
/// and OEM recognizers sometimes do punctuate.
String appendSegment(String existing, String segment) {
  final add = segment.trim();
  if (add.isEmpty) return existing;
  final base = existing.trimRight();
  final cjk = isCjkText(add) || isCjkText(base);

  if (base.isEmpty) return cjk ? add : _capitalize(add);

  final endsTerminated = _anyTerminal.contains(base[base.length - 1]);
  final joiner = endsTerminated ? (cjk ? '' : ' ') : (cjk ? '。' : '. ');
  return '$base$joiner${cjk ? add : _capitalize(add)}';
}

/// Finishes a note: trims and gives the last sentence a terminator so the text
/// does not end mid-air.
String finalizeTranscript(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (_anyTerminal.contains(t[t.length - 1])) return t;
  return isCjkText(t) ? '$t。' : '$t.';
}

/// What the user sees while speaking: the text committed so far plus the live
/// partial guess of the current utterance.
String previewTranscript(String committed, String partial) {
  final p = partial.trim();
  if (p.isEmpty) return committed;
  return appendSegment(committed, p);
}

/// First sentence of [text], trimmed to a card-title length.
String firstSentenceTitle(String text, {String emptyLabel = '(empty)'}) {
  var t = text.trim();
  // Skip leading punctuation/blank lines so a stray "。" never becomes a title.
  while (t.isNotEmpty && (_sentenceEnders.contains(t[0]) || t[0] == '\n')) {
    t = t.substring(1).trimLeft();
  }
  if (t.isEmpty) return emptyLabel;
  final buf = StringBuffer();
  for (final ch in t.split('')) {
    if (_sentenceEnders.contains(ch) || ch == '\n') break;
    buf.write(ch);
  }
  final first = (buf.isEmpty ? t : buf.toString()).trim();
  if (first.isEmpty) return emptyLabel;
  return first.length <= 24 ? first : '${first.substring(0, 24)}…';
}

/// Rough word/character count for the note card ("42 字" / "42 words").
int countUnits(String text, {required bool cjk}) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  if (cjk) {
    return t.replaceAll(RegExp(r'\s+'), '').runes.length;
  }
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
