import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/l10n.dart';
import 'transcript_text.dart';

/// A dictated note. Text only — the app never keeps an audio file (the system
/// on-device recognizer transcribes live; see dictation.dart).
class Note {
  Note({
    required this.id,
    required this.createdAt,
    this.durationMs = 0,
    this.text = '',
    this.language = '',
  });

  final String id;
  final DateTime createdAt;

  /// How long the dictation lasted, for the card subtitle.
  int durationMs;
  String text;

  /// Language tag the recognizer was asked for ("zh-CN"), kept for the detail
  /// screen and for export metadata.
  String language;

  String get title => firstSentenceTitle(
        text,
        emptyLabel: tr(zh: '(空白笔记)', en: '(empty note)'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'text': text,
        'language': language,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: (j['id'] as String?) ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt:
            DateTime.tryParse((j['createdAt'] as String?) ?? '') ??
                DateTime.now(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        text: (j['text'] as String?) ?? '',
        // Pre-1.0 records carried an audioPath / status; both are gone now and
        // are simply ignored here.
        language: (j['language'] as String?) ?? '',
      );
}

/// JSON-file backed note store in the app sandbox. Fine at the thousands-of-
/// notes scale and keeps the app free of database dependencies.
///
/// Durability rules (a note is often the only copy of a thought):
///  - every write is queued, so two overlapping saves can never interleave;
///  - every write goes to a temp file and is then renamed over the index, so a
///    crash mid-write leaves the previous good file intact;
///  - an unreadable index is moved aside (not overwritten) and reported through
///    [loadError] instead of silently starting empty.
class NoteStore extends ChangeNotifier {
  NoteStore._(this._indexFile, this._notes, this._pro, {this.loadError});

  final File _indexFile;
  final List<Note> _notes;
  bool _pro;

  /// Set when the previous index could not be read. The UI surfaces it; the
  /// original file is kept as `notes.corrupt-<millis>.json` for recovery.
  final String? loadError;

  Future<void> _writeQueue = Future<void>.value();

  List<Note> get notes => List.unmodifiable(_notes);

  /// Pro unlock (one-time purchase). Persisted alongside the notes.
  bool get pro => _pro;

  @visibleForTesting
  static NoteStore forTest(File indexFile, List<Note> notes,
          {bool pro = false, String? loadError}) =>
      NoteStore._(indexFile, notes, pro, loadError: loadError);

  static Future<NoteStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final indexFile = File('${docs.path}/notes.json');
    var notes = <Note>[];
    var pro = false;
    String? loadError;
    if (await indexFile.exists()) {
      try {
        final decoded = jsonDecode(await indexFile.readAsString());
        // v1 format: {"pro": bool, "notes": [...]}. The pre-release build wrote
        // a bare list — still readable.
        final List raw;
        if (decoded is Map) {
          pro = decoded['pro'] == true;
          raw = (decoded['notes'] as List?) ?? const [];
        } else {
          raw = decoded as List;
        }
        notes = raw
            .whereType<Map>()
            .map((e) => Note.fromJson(e.cast<String, dynamic>()))
            .toList();
      } catch (e) {
        // Unreadable index: keep the bytes (never overwrite them) and tell the
        // user, instead of quietly starting from nothing.
        debugPrint('note index unreadable: $e');
        loadError = await _quarantine(indexFile);
      }
    }
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Clean up audio files written by the pre-release whisper build — nothing
    // plays them back any more.
    unawaited(_removeLegacyAudio(docs.path));
    return NoteStore._(indexFile, notes, pro, loadError: loadError);
  }

  /// Best-effort store for the case where even the app directory is unavailable:
  /// the app still runs, it just cannot persist (and says so).
  static NoteStore volatileFallback(Object error) => NoteStore._(
        File('${Directory.systemTemp.path}/echojot_fallback.json'),
        <Note>[],
        false,
        loadError: '$error',
      );

  static Future<String?> _quarantine(File indexFile) async {
    final backup =
        '${indexFile.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await indexFile.rename(backup);
      return backup;
    } catch (e) {
      debugPrint('could not quarantine bad index: $e');
      return indexFile.path;
    }
  }

  static Future<void> _removeLegacyAudio(String docsPath) async {
    try {
      final dir = Directory('$docsPath/audio');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('legacy audio cleanup skipped: $e');
    }
  }

  /// Queued + atomic save. Returns when this particular save has landed.
  Future<void> _persist() {
    final done = _writeQueue.then((_) => _write());
    // Keep the chain alive even if one write fails.
    _writeQueue = done.catchError((Object e) {
      debugPrint('note persist failed: $e');
    });
    return _writeQueue;
  }

  Future<void> _write() async {
    final payload = jsonEncode({
      'pro': _pro,
      'notes': _notes.map((n) => n.toJson()).toList(),
    });
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    // rename() replaces the target atomically on Android — a crash mid-write
    // can therefore never truncate the live index.
    await tmp.rename(_indexFile.path);
  }

  Future<void> add(Note note) async {
    _notes.insert(0, note);
    notifyListeners();
    await _persist();
  }

  /// Persist in-place edits to [note] (text was mutated by the caller).
  Future<void> update(Note note) async {
    notifyListeners();
    await _persist();
  }

  Future<void> remove(Note note) async {
    _notes.remove(note);
    notifyListeners();
    await _persist();
  }

  /// Undo support for swipe-to-delete: puts [note] back where it was.
  Future<void> insertAt(int index, Note note) async {
    _notes.insert(index.clamp(0, _notes.length), note);
    notifyListeners();
    await _persist();
  }

  int indexOf(Note note) => _notes.indexOf(note);

  Future<void> unlockPro() async {
    if (_pro) return;
    _pro = true;
    notifyListeners();
    await _persist();
  }

  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return _notes
        .where((n) => n.text.toLowerCase().contains(q))
        .toList(growable: false);
  }
}
