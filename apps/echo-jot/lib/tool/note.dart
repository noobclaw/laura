import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Transcription lifecycle of a note.
enum NoteStatus { pending, transcribing, done, failed }

class Note {
  Note({
    required this.id,
    required this.createdAt,
    required this.audioPath,
    this.durationMs = 0,
    this.text = '',
    this.status = NoteStatus.pending,
  });

  final String id;
  final DateTime createdAt;
  final String audioPath;
  int durationMs;
  String text;
  NoteStatus status;

  String get title => firstSentenceTitle(text);

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'audioPath': audioPath,
        'durationMs': durationMs,
        'text': text,
        'status': status.name,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        audioPath: j['audioPath'] as String,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        text: (j['text'] as String?) ?? '',
        status: NoteStatus.values.asNameMap()[j['status']] ?? NoteStatus.done,
      );
}

/// First sentence of [text], trimmed to a card-title length.
String firstSentenceTitle(String text) {
  final t = text.trim();
  if (t.isEmpty) return '(未转写)';
  final match = RegExp(r'[^。！？.!?\n]+').firstMatch(t);
  final first = (match?.group(0) ?? t).trim();
  return first.length <= 24 ? first : '${first.substring(0, 24)}…';
}

/// JSON-file backed note store. Fine for the thousands-of-notes scale;
/// keeps the app free of database dependencies.
class NoteStore extends ChangeNotifier {
  NoteStore._(this._indexFile, this.audioDir, this._notes);

  final File _indexFile;
  final Directory audioDir;
  final List<Note> _notes;

  List<Note> get notes => List.unmodifiable(_notes);

  static Future<NoteStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${docs.path}/audio');
    await audioDir.create(recursive: true);
    final indexFile = File('${docs.path}/notes.json');
    var notes = <Note>[];
    if (await indexFile.exists()) {
      try {
        final raw = jsonDecode(await indexFile.readAsString()) as List;
        notes = raw
            .map((e) => Note.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Corrupt index: keep audio files, start with an empty list.
      }
    }
    // Recording could have been interrupted mid-transcription last run.
    for (final n in notes) {
      if (n.status == NoteStatus.transcribing) n.status = NoteStatus.pending;
    }
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return NoteStore._(indexFile, audioDir, notes);
  }

  Future<void> _persist() async {
    await _indexFile
        .writeAsString(jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  Future<void> add(Note note) async {
    _notes.insert(0, note);
    await _persist();
    notifyListeners();
  }

  Future<void> update(Note note) async {
    await _persist();
    notifyListeners();
  }

  Future<void> remove(Note note) async {
    _notes.remove(note);
    try {
      final f = File(note.audioPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _persist();
    notifyListeners();
  }

  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return _notes
        .where((n) => n.text.toLowerCase().contains(q))
        .toList(growable: false);
  }
}
