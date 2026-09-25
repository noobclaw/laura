import 'package:flutter/foundation.dart';

import '../core/l10n.dart';

/// Where a scene is in the writing process. Shown as a coloured dot in the
/// outline so a 60-scene book can be scanned at a glance.
enum SceneStatus { todo, drafting, done }

SceneStatus sceneStatusFromName(String? name) => switch (name) {
      'drafting' => SceneStatus.drafting,
      'done' => SceneStatus.done,
      _ => SceneStatus.todo,
    };

String sceneStatusLabel(SceneStatus s) => switch (s) {
      SceneStatus.todo => tr(zh: '待写', en: 'To write'),
      SceneStatus.drafting => tr(zh: '草稿', en: 'Draft'),
      SceneStatus.done => tr(zh: '已完成', en: 'Done'),
    };

/// One saved version of a scene's body. Kept locally, capped per scene — the
/// answer to "Restoring from a month old backup - devastating to lose a month
/// of writing" (PLAN.md 证据②).
@immutable
class SceneSnapshot {
  const SceneSnapshot({required this.ms, required this.body, this.note = ''});

  /// Wall-clock time the snapshot was taken.
  final int ms;
  final String body;

  /// Why it was taken ('' = saved on leaving the editor; otherwise a marker
  /// such as the version this one replaced when the writer restored).
  final String note;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(ms);
  int get words => countWords(body);

  Map<String, dynamic> toJson() => {
        'ms': ms,
        'body': body,
        if (note.isNotEmpty) 'note': note,
      };

  static SceneSnapshot fromJson(Map<String, dynamic> j) => SceneSnapshot(
        ms: (j['ms'] as num?)?.toInt() ?? 0,
        body: j['body'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

/// The smallest unit of writing: a scene (Scrivener calls it a document).
class Scene {
  Scene({
    required this.id,
    this.title = '',
    String synopsis = '',
    String body = '',
    this.status = SceneStatus.todo,
    List<SceneSnapshot>? history,
    int? createdMs,
    int? updatedMs,
    // The two below cannot be initializing formals: the fields are private
    // (they sit behind setters that keep the cached word count and summary in
    // step) and a named parameter may not start with an underscore.
  })  :
        // ignore: prefer_initializing_formals
        _synopsis = synopsis,
        // ignore: prefer_initializing_formals
        _body = body,
        history = history ?? <SceneSnapshot>[],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch,
        updatedMs = updatedMs ?? createdMs ?? DateTime.now().millisecondsSinceEpoch;

  /// How many versions of one scene we keep on device. Twenty covers weeks of
  /// daily writing at a few KB each; older ones roll off the front.
  static const int maxHistory = 20;

  final String id;
  String title;
  SceneStatus status;
  final List<SceneSnapshot> history;
  final int createdMs;
  int updatedMs;

  /// Where the caret was when the writer last left this scene, so "Keep
  /// writing" puts it back there. Null: never recorded, go to the end.
  int? caret;

  String _synopsis;
  String _body;
  int? _words;
  String? _summary;

  String get synopsis => _synopsis;

  set synopsis(String value) {
    if (_synopsis == value) return;
    _synopsis = value;
    _summary = null;
  }

  String get body => _body;

  set body(String value) {
    if (_body == value) return;
    _body = value;
    _words = null;
    _summary = null;
  }

  /// Cached: the outline redraws on every autosave, and recounting every scene
  /// of a 200-scene book on each of those rebuilds is the difference between a
  /// list that scrolls and one that stutters while you type.
  int get words => _words ??= countWords(_body);

  int get chars => countChars(_body);

  /// One line of the scene for the outline: its synopsis if it has one, else
  /// the opening of the text with the Markdown marks and line breaks taken out.
  /// Cached with the body for the same reason as [words].
  String summary({String Function(String)? strip}) {
    final existing = _summary;
    if (existing != null) return existing;
    final synopsisText = synopsis.trim();
    if (synopsisText.isNotEmpty) return _summary = synopsisText;
    final head = _body.length > 200 ? _body.substring(0, 200) : _body;
    final plain = strip == null ? head : strip(head);
    return _summary = plain.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String displayTitle(int index) =>
      title.trim().isEmpty ? tr(zh: '场景 ${index + 1}', en: 'Scene ${index + 1}') : title.trim();

  /// The scene as it goes into the manuscript document. Version history is
  /// deliberately NOT included: it is written to its own file, so an autosave
  /// re-encodes the live text rather than twenty copies of it.
  Map<String, dynamic> toJson({bool withHistory = false}) => {
        'id': id,
        'title': title,
        'synopsis': synopsis,
        'body': body,
        'status': status.name,
        'createdMs': createdMs,
        'updatedMs': updatedMs,
        if (caret != null) 'caret': caret,
        if (withHistory) 'history': history.map((s) => s.toJson()).toList(),
      };

  static Scene fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'] as String? ?? 'scn-${DateTime.now().microsecondsSinceEpoch}',
        title: j['title'] as String? ?? '',
        synopsis: j['synopsis'] as String? ?? '',
        body: j['body'] as String? ?? '',
        status: sceneStatusFromName(j['status'] as String?),
        createdMs: (j['createdMs'] as num?)?.toInt(),
        updatedMs: (j['updatedMs'] as num?)?.toInt(),
        history: (j['history'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SceneSnapshot.fromJson)
            .toList(),
      )..caret = (j['caret'] as num?)?.toInt();
}

/// A chapter: an ordered bag of scenes.
class Chapter {
  Chapter({
    required this.id,
    this.title = '',
    List<Scene>? scenes,
    this.collapsed = false,
  }) : scenes = scenes ?? <Scene>[];

  final String id;
  String title;
  final List<Scene> scenes;

  /// Collapsed chapters keep the outline of a long book scannable. Persisted,
  /// because re-expanding twelve chapters on every launch is its own annoyance.
  bool collapsed;

  int get words => scenes.fold(0, (a, s) => a + s.words);

  String displayTitle(int index) => title.trim().isEmpty
      ? tr(zh: '第 ${index + 1} 章', en: 'Chapter ${index + 1}')
      : title.trim();

  Map<String, dynamic> toJson({bool withHistory = false}) => {
        'id': id,
        'title': title,
        'collapsed': collapsed,
        'scenes':
            scenes.map((s) => s.toJson(withHistory: withHistory)).toList(),
      };

  static Chapter fromJson(Map<String, dynamic> j) => Chapter(
        id: j['id'] as String? ?? 'chp-${DateTime.now().microsecondsSinceEpoch}',
        title: j['title'] as String? ?? '',
        collapsed: j['collapsed'] as bool? ?? false,
        scenes: (j['scenes'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Scene.fromJson)
            .toList(),
      );
}

/// A project is one book.
class Project {
  Project({
    required this.id,
    this.title = '',
    this.note = '',
    this.targetWords = 0,
    List<Chapter>? chapters,
    int? createdMs,
    int? updatedMs,
    this.lastSceneId,
  })  : chapters = chapters ?? <Chapter>[],
        createdMs = createdMs ?? DateTime.now().millisecondsSinceEpoch,
        updatedMs = updatedMs ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String title;
  String note;

  /// Whole-book word target; 0 means "no target set".
  int targetWords;
  final List<Chapter> chapters;
  final int createdMs;
  int updatedMs;

  /// Where the cursor was last: "open the app → back at the last scene" in
  /// two taps (PLAN.md 交互铁律 3).
  String? lastSceneId;

  int get words => chapters.fold(0, (a, c) => a + c.words);
  int get sceneCount => chapters.fold(0, (a, c) => a + c.scenes.length);

  /// 0..1 against [targetWords], or null when no target is set.
  double? get progress {
    if (targetWords <= 0) return null;
    return (words / targetWords).clamp(0.0, 1.0);
  }

  String get displayTitle =>
      title.trim().isEmpty ? tr(zh: '未命名项目', en: 'Untitled project') : title.trim();

  Map<String, dynamic> toJson({bool withHistory = false}) => {
        'id': id,
        'title': title,
        'note': note,
        'targetWords': targetWords,
        'createdMs': createdMs,
        'updatedMs': updatedMs,
        if (lastSceneId != null) 'lastSceneId': lastSceneId,
        'chapters':
            chapters.map((c) => c.toJson(withHistory: withHistory)).toList(),
      };

  static Project fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String? ?? 'prj-${DateTime.now().microsecondsSinceEpoch}',
        title: j['title'] as String? ?? '',
        note: j['note'] as String? ?? '',
        targetWords: (j['targetWords'] as num?)?.toInt() ?? 0,
        createdMs: (j['createdMs'] as num?)?.toInt(),
        updatedMs: (j['updatedMs'] as num?)?.toInt(),
        lastSceneId: j['lastSceneId'] as String?,
        chapters: (j['chapters'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Chapter.fromJson)
            .toList(),
      );
}

/// A scene together with where it sits, for screens that only got an id.
@immutable
class SceneRef {
  const SceneRef({
    required this.project,
    required this.chapter,
    required this.scene,
    required this.chapterIndex,
    required this.sceneIndex,
  });

  final Project project;
  final Chapter chapter;
  final Scene scene;
  final int chapterIndex;
  final int sceneIndex;
}

// ---------------------------------------------------------------------------
// Counting
// ---------------------------------------------------------------------------

bool _isCjk(int r) =>
    (r >= 0x3400 && r <= 0x4DBF) || // CJK ext A
    (r >= 0x4E00 && r <= 0x9FFF) || // CJK unified
    (r >= 0xF900 && r <= 0xFAFF) || // compatibility ideographs
    (r >= 0x3040 && r <= 0x30FF) || // kana
    (r >= 0xAC00 && r <= 0xD7AF) || // hangul syllables
    (r >= 0x20000 && r <= 0x2FA1F); // CJK ext B+

bool _isSpace(int r) =>
    r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0x0C ||
    r == 0x00A0 || r == 0x3000 || (r >= 0x2000 && r <= 0x200A);

/// ASCII and CJK punctuation that must not, on its own, count as a word.
const Set<int> _punct = {
  0x21, 0x22, 0x23, 0x25, 0x26, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E,
  0x2F, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x5B, 0x5C, 0x5D, 0x5E,
  0x5F, 0x60, 0x7B, 0x7C, 0x7D, 0x7E,
  0x2018, 0x2019, 0x201C, 0x201D, 0x2013, 0x2014, 0x2026, 0x00B7,
  0x3001, 0x3002, 0xFF0C, 0xFF01, 0xFF1F, 0xFF1A, 0xFF1B, 0xFF08, 0xFF09,
  0x300A, 0x300B, 0x3008, 0x3009, 0x300C, 0x300D, 0x300E, 0x300F,
};

/// Words the way a writer counts them: every CJK character is one word, every
/// run of Latin/digits between separators is one word, and a lone dash or
/// ellipsis is not a word at all.
///
/// Both conventions have to live in one number because a Chinese writer's
/// "十万字" and an English writer's "80k words" are the same progress bar.
int countWords(String text) {
  var words = 0;
  var inRun = false;
  var runHasLetter = false;

  void flush() {
    if (inRun && runHasLetter) words++;
    inRun = false;
    runHasLetter = false;
  }

  for (final r in text.runes) {
    if (_isCjk(r)) {
      flush();
      words++;
    } else if (_isSpace(r)) {
      flush();
    } else {
      inRun = true;
      if (!_punct.contains(r)) runHasLetter = true;
    }
  }
  flush();
  return words;
}

/// Characters excluding whitespace — the count Chinese-language editors ask
/// for, and the one that makes a 100-character scene feel like 100.
int countChars(String text) {
  var n = 0;
  for (final r in text.runes) {
    if (!_isSpace(r)) n++;
  }
  return n;
}

/// Thousands separator for counts, locale-neutral ("12,480").
String groupedCount(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// `2026-09-16` — the key the daily writing log is bucketed by. Local time on
/// purpose: a writer's "today" is their calendar day, not UTC's.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
