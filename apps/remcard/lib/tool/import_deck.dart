/// Parsing for "bring your own deck" imports — the one thing AnkiMobile users
/// complain they cannot do on the phone ("Must download desktop app to use
/// shared decks"). Everything here is pure Dart on strings/bytes: no network,
/// no platform channels, so it is fully unit-testable and cannot leak data.
/// The file/zip/SQLite plumbing lives in apkg_import.dart and import_flow.dart.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One card recovered from an import file.
class ImportedCard {
  const ImportedCard(this.front, this.back);

  final String front;
  final String back;
}

/// Outcome of parsing one file: the cards we could read, plus an honest count
/// of what we threw away so the UI can say "imported 120, skipped 3" instead
/// of silently losing rows.
class ImportResult {
  const ImportResult({
    required this.cards,
    this.skippedRows = 0,
    this.formatLabel = '',
  });

  final List<ImportedCard> cards;

  /// Rows/notes that had no usable front/back pair.
  final int skippedRows;

  /// Human-readable format we detected ("TSV", "CSV (;)", "Anki"), shown in
  /// the preview so a user with a semicolon-separated European CSV can tell
  /// we got it right.
  final String formatLabel;

  bool get isEmpty => cards.isEmpty;
}

/// Why an import failed. The UI maps each case to a localized, actionable
/// message; the parsers stay free of `tr()` so they can be unit-tested.
enum ImportProblem {
  /// The file had no text at all.
  emptyFile,

  /// We read the file but not one row had both a front and a back.
  noCards,

  /// Picked as .apkg but is not a zip with an Anki collection inside.
  notAnApkg,

  /// A zstd-compressed `collection.anki21b` (Anki ≥ 2.1.50 default export)
  /// which we cannot decompress on-device. The fix is on the user's side:
  /// re-export with "support older Anki versions" ticked, or export as text.
  newApkgFormat,

  /// The SQLite inside the .apkg would not open or lacks a `notes` table.
  badDatabase,

  /// Anything else (picker gave no path, read error, …). [ImportException.detail]
  /// carries the raw error for the message.
  unreadable,
}

/// Thrown by every parser when a file cannot be imported at all.
class ImportException implements Exception {
  ImportException(this.problem, [this.detail]);

  final ImportProblem problem;
  final String? detail;

  @override
  String toString() => 'ImportException(${problem.name}${detail == null ? '' : ': $detail'})';
}

// ---------------------------------------------------------------------------
// Text decoding
// ---------------------------------------------------------------------------

/// Decodes a text file's bytes, honouring a UTF-16 byte-order mark.
///
/// Excel's "Unicode Text (*.txt)" export — the path most people take to get
/// a tab-separated file out of a spreadsheet — is UTF-16LE. Feeding that to a
/// UTF-8 decoder yields one garbage card per row, so detect it up front.
/// Everything else is treated as UTF-8 with malformed bytes replaced rather
/// than thrown, so a single bad byte does not kill a 2,000-row import.
String decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes, 2, littleEndian: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes, 2, littleEndian: false);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _utf16(Uint8List b, int offset, {required bool littleEndian}) {
  final n = (b.length - offset) ~/ 2;
  final units = List<int>.generate(n, (i) {
    final lo = b[offset + 2 * i];
    final hi = b[offset + 2 * i + 1];
    return littleEndian ? lo | (hi << 8) : (lo << 8) | hi;
  });
  return String.fromCharCodes(units);
}

/// Strips a UTF-8 byte-order mark. Files exported from Excel almost always
/// carry one, and leaving it in turns the first field into "﻿Hello".
String stripBom(String input) =>
    input.startsWith('﻿') ? input.substring(1) : input;

// ---------------------------------------------------------------------------
// CSV / TSV
// ---------------------------------------------------------------------------

/// Picks the separator by counting candidates outside quoted sections on the
/// first few lines. Anki exports tab-separated files, Excel writes commas, and
/// European locales write semicolons — guessing wrong silently produces
/// one-column rows, so this is worth doing properly rather than assuming ','.
String detectDelimiter(String text) {
  const candidates = ['\t', ',', ';'];
  final sample = _firstLines(text, 20);
  var best = ',';
  var bestScore = -1;
  for (final d in candidates) {
    final score = _countOutsideQuotes(sample, d);
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return bestScore <= 0 ? '\t' : best;
}

String _firstLines(String text, int n) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n') {
      count++;
      if (count >= n) return text.substring(0, i);
    }
  }
  return text;
}

int _countOutsideQuotes(String text, String delimiter) {
  var inQuotes = false;
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      // A doubled quote inside a quoted field is an escaped quote, not a close.
      if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
        i++;
        continue;
      }
      inQuotes = !inQuotes;
    } else if (!inQuotes && ch == delimiter) {
      count++;
    }
  }
  return count;
}

/// Splits delimited text into rows of fields, honouring RFC 4180 quoting:
/// quoted fields may contain the delimiter, newlines, and `""` escapes.
///
/// Handles LF, CRLF and lone-CR line endings, because a file that came off a
/// Mac Classic export or a Windows editor should not silently become one row.
List<List<String>> parseDelimited(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      i++;
      continue;
    }
    if (ch == delimiter) {
      endField();
      i++;
      continue;
    }
    if (ch == '\r') {
      // Swallow CRLF as one break; a lone CR also ends the row.
      endRow();
      i += (i + 1 < text.length && text[i + 1] == '\n') ? 2 : 1;
      continue;
    }
    if (ch == '\n') {
      endRow();
      i++;
      continue;
    }
    field.write(ch);
    i++;
  }
  // Trailing field/row unless the file ended exactly on a line break.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

final _tagPattern = RegExp(r'<[^>]*>');
// Anki wraps each visual line in <div>…</div>, so both the opening and the
// closing tag mark a line break; the double newline that produces is
// collapsed below.
final _brPattern =
    RegExp(r'<br\s*/?>|</?div[^>]*>|</?p[^>]*>', caseSensitive: false);
final _wsPattern = RegExp(r'[ \t]+');
final _blankLines = RegExp(r'\n{2,}');

/// Anki fields are HTML. Cards imported with raw markup in them read as
/// `Hello<br>world<div>…` on the study screen, so flatten to plain text:
/// block breaks become newlines, remaining tags are dropped, entities decoded.
String htmlToPlainText(String input) {
  var s = input.replaceAll(_brPattern, '\n');
  s = s.replaceAll(_tagPattern, '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      // Ampersand last, so "&amp;lt;" does not collapse into "<".
      .replaceAll('&amp;', '&');
  s = s.replaceAll(_wsPattern, ' ');
  return s
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(_blankLines, '\n')
      .trim();
}

/// Anki's own text exports start with `#` comment lines (`#separator:tab`,
/// `#html:true`). They are metadata, not cards.
bool _isCommentRow(List<String> row) =>
    row.isNotEmpty && row.first.trimLeft().startsWith('#');

/// Parses CSV/TSV text into cards. The first two non-empty columns become
/// front and back; extra columns (Anki writes tags and a deck name) are
/// ignored rather than being crammed into the answer.
///
/// Throws [ImportException] when nothing at all could be read, so the UI
/// never shows an empty success.
ImportResult parseDelimitedCards(String rawText, {String? delimiter}) {
  final text = stripBom(rawText);
  if (text.trim().isEmpty) throw ImportException(ImportProblem.emptyFile);
  final d = delimiter ?? detectDelimiter(text);
  final rows = parseDelimited(text, d);

  final cards = <ImportedCard>[];
  var skipped = 0;
  for (final row in rows) {
    if (_isCommentRow(row)) continue;
    final cells = row.map(htmlToPlainText).toList();
    final front = cells.isNotEmpty ? cells[0].trim() : '';
    final back = cells.length > 1 ? cells[1].trim() : '';
    if (front.isEmpty && back.isEmpty) continue; // blank line, not a loss
    if (front.isEmpty || back.isEmpty) {
      skipped++; // a real row we could not use — tell the user
      continue;
    }
    cards.add(ImportedCard(front, back));
  }

  if (cards.isEmpty) throw ImportException(ImportProblem.noCards);
  return ImportResult(
    cards: cards,
    skippedRows: skipped,
    formatLabel: _delimiterLabel(d),
  );
}

String _delimiterLabel(String d) {
  switch (d) {
    case '\t':
      return 'TSV';
    case ';':
      return 'CSV (;)';
    default:
      return 'CSV (,)';
  }
}

// ---------------------------------------------------------------------------
// Anki notes (the pure half of .apkg import)
// ---------------------------------------------------------------------------

/// Anki separates the fields of one note with U+001F.
const ankiFieldSeparator = '';

/// `{{c1::answer}}` or `{{c1::answer::hint}}`.
final _clozePattern = RegExp(r'\{\{c\d+::(.*?)(?:::(.*?))?\}\}', dotAll: true);

/// Splits a `notes.flds` value into its fields.
List<String> splitAnkiFields(String flds) => flds.split(ankiFieldSeparator);

/// Turns one Anki note's fields into a card, or null if it has no usable
/// front/back.
///
/// Basic notes: field 0 → front, field 1 → back. Cloze notes (field 0 holds
/// `{{c1::…}}`) become "fill the blank": the front shows `[…]` (or the hint)
/// in place of each deletion and the back reveals it, with the Extra field
/// appended when present. Multi-cloze notes collapse into one card — good
/// enough for v1, and honest in the preview count.
ImportedCard? cardFromAnkiFields(List<String> fields) {
  if (fields.isEmpty) return null;
  final f0 = fields[0];
  if (_clozePattern.hasMatch(f0)) {
    final front = htmlToPlainText(f0.replaceAllMapped(
      _clozePattern,
      (m) => (m.group(2)?.isNotEmpty ?? false) ? '[${m.group(2)}]' : '[…]',
    ));
    var back =
        htmlToPlainText(f0.replaceAllMapped(_clozePattern, (m) => m.group(1)!));
    final extra = fields.length > 1 ? htmlToPlainText(fields[1]) : '';
    if (extra.isNotEmpty) back = '$back\n$extra';
    if (front.isEmpty || back.isEmpty) return null;
    return ImportedCard(front, back);
  }
  final front = htmlToPlainText(f0);
  final back = fields.length > 1 ? htmlToPlainText(fields[1]) : '';
  if (front.isEmpty || back.isEmpty) return null;
  return ImportedCard(front, back);
}

/// Anki nests decks as `Parent::Child` (legacy) or with U+001F (2.1.28+ schema).
/// Show the leaf — "Japanese::N5::Verbs" as a deck name on a phone is noise.
String ankiDeckLeafName(String raw) {
  final parts = raw.split(RegExp('::|'));
  return parts.isEmpty ? raw.trim() : parts.last.trim();
}

/// Guesses a deck name from the file name: `HSK1 vocab.csv` → `HSK1 vocab`.
String deckNameFromFileName(String fileName, String fallback) {
  var name = fileName.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot >= 0) name = name.substring(0, dot);
  name = name.replaceAll('_', ' ').trim();
  return name.isEmpty ? fallback : name;
}
