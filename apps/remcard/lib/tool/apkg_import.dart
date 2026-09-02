import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:sqlite3/sqlite3.dart';

import 'import_deck.dart';

/// What we recovered from one .apkg.
class ApkgDeck {
  const ApkgDeck({
    required this.result,
    required this.deckCount,
    this.suggestedName,
  });

  final ImportResult result;

  /// How many (non-Default) decks the collection declared. Everything is
  /// merged into one Remcard deck; the preview tells the user when it was >1.
  final int deckCount;

  /// The collection's own deck name when there was exactly one — better than
  /// the file name, which for AnkiWeb downloads is often a numeric id.
  final String? suggestedName;
}

/// Reads an Anki package: a zip holding a SQLite collection plus media.
///
/// Only the `notes` table is used, so media files (which can be hundreds of
/// MB) are never inflated — the zip is walked as a stream from disk.
/// [scratchDir] is where the SQLite file is unpacked, because sqlite3 needs a
/// path; it is deleted before returning.
Future<ApkgDeck> readApkg(String path, Directory scratchDir) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeStream(InputFileStream(path));
  } catch (_) {
    throw ImportException(ImportProblem.notAnApkg);
  }

  ArchiveFile? find(String name) {
    for (final f in archive) {
      if (f.name == name) return f;
    }
    return null;
  }

  // Prefer the 2.1 schema when both are present (legacy exports ship both;
  // the .anki2 copy is then a compatibility stub with no notes).
  final dbEntry = find('collection.anki21') ?? find('collection.anki2');
  if (dbEntry == null) {
    if (find('collection.anki21b') != null) {
      throw ImportException(ImportProblem.newApkgFormat);
    }
    throw ImportException(ImportProblem.notAnApkg);
  }

  final bytes = dbEntry.readBytes();
  if (bytes == null || bytes.isEmpty) {
    throw ImportException(ImportProblem.badDatabase);
  }
  final tmp = File(
    '${scratchDir.path}/remcard-import-'
    '${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
  await tmp.writeAsBytes(bytes, flush: true);
  try {
    return _readCollection(tmp.path);
  } finally {
    try {
      await tmp.delete();
    } catch (_) {
      // Best effort; the OS clears the temp dir anyway.
    }
  }
}

ApkgDeck _readCollection(String dbPath) {
  final Database db;
  try {
    db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  } catch (_) {
    throw ImportException(ImportProblem.badDatabase);
  }
  try {
    final ResultSet rows;
    try {
      rows = db.select('SELECT flds FROM notes');
    } catch (_) {
      throw ImportException(ImportProblem.badDatabase);
    }
    final cards = <ImportedCard>[];
    var skipped = 0;
    for (final row in rows) {
      final card =
          cardFromAnkiFields(splitAnkiFields(row['flds'] as String? ?? ''));
      if (card == null) {
        skipped++;
        continue;
      }
      cards.add(card);
    }
    if (cards.isEmpty) throw ImportException(ImportProblem.noCards);

    final names = _deckNames(db);
    return ApkgDeck(
      result: ImportResult(
        cards: cards,
        skippedRows: skipped,
        formatLabel: 'Anki',
      ),
      deckCount: names.length,
      suggestedName: names.length == 1 ? names.single : null,
    );
  } finally {
    db.dispose();
  }
}

/// Deck names excluding Anki's built-in "Default". The legacy schema keeps
/// them as JSON in `col.decks`; 2.1.28+ moved them to a `decks` table. Either
/// may be missing from a hand-made package, so failure here just means "no
/// suggestion", never a failed import.
List<String> _deckNames(Database db) {
  final names = <String>{};
  try {
    for (final row in db.select('SELECT name FROM decks')) {
      final n = row['name'];
      if (n is String) names.add(n);
    }
  } catch (_) {
    try {
      final r = db.select('SELECT decks FROM col LIMIT 1');
      if (r.isNotEmpty) {
        final m = jsonDecode(r.first['decks'] as String) as Map<String, dynamic>;
        for (final v in m.values) {
          final n = (v as Map)['name'];
          if (n is String) names.add(n);
        }
      }
    } catch (_) {
      // No deck metadata — fall back to the file name upstream.
    }
  }
  names.remove('Default');
  return names
      .map(ankiDeckLeafName)
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList();
}
