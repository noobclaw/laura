import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/json_file_store.dart';
import 'models.dart';

/// Something went wrong with the one file the manuscript lives in.
///
/// `kind` is `save` (the document could not be written), `load` (it could not
/// be read at all) or `corrupt` (it would not parse and was kept aside under
/// the path in [detail]). `detail` is the platform's own message or the path —
/// never swallowed, because "your book did not save" with no reason is worse
/// than the failure itself.
@immutable
class StorageTrouble {
  const StorageTrouble({required this.kind, required this.detail});

  final String kind;
  final String detail;
}

/// Every project, chapter, scene and snapshot, backed by one atomically
/// written JSON document in the app's own storage. Nothing here touches the
/// network — M1 is deliberately single-device (PLAN.md §6).
///
/// A 100,000-word book is roughly 200 KB of text, so one document per install
/// stays comfortably small even with a shelf of books and their version
/// history.
class DraftbookStore extends ChangeNotifier {
  DraftbookStore();

  /// The free tier keeps one book. Everything else about it is unlimited —
  /// words, chapters, scenes, version history, TXT/Markdown export.
  static const int freeProjects = 1;

  /// Default daily target, in words. A round number a first-time user can
  /// beat on day one.
  static const int defaultDailyGoal = 500;

  /// Days of writing log we keep; a year of streaks is plenty and keeps the
  /// document from growing without bound.
  static const int maxLogDays = 400;

  final List<Project> projects = [];
  final Map<String, int> dailyLog = {};

  bool pro = false;
  bool loaded = false;
  int dailyGoal = defaultDailyGoal;

  /// The manuscript: projects, chapters, scenes and their live text.
  late final JsonFileStore _file = JsonFileStore(
    'draftbook.json',
    onTrouble: _onStorageTrouble,
    onWritten: _onStorageWritten,
  );

  /// Version history, keyed by scene id, in its own document.
  ///
  /// Twenty snapshots per scene is twenty extra copies of that scene's text, so
  /// keeping them inside the manuscript would mean re-encoding ~20× the book on
  /// every autosave — on the UI isolate, while someone is typing. History
  /// changes only when a version is taken or dropped, so it gets its own file
  /// and the hot path encodes the live text alone.
  late final JsonFileStore _historyFile =
      JsonFileStore('draftbook_history.json', onTrouble: _onStorageTrouble);

  /// The Pro flag, on its own, so a damaged manuscript cannot revoke a
  /// purchase. (It is still recoverable through "Restore purchases", but a
  /// paying writer should never have to discover that.)
  late final JsonFileStore _proFile = JsonFileStore('draftbook_pro.json');

  Timer? _saveTimer;

  /// Set when the manuscript could not be written, or when a damaged document
  /// had to be set aside. Null the rest of the time.
  ///
  /// An app whose one promise is "nothing you wrote is ever lost" cannot let a
  /// failed save reach only `debugPrint`: the writer would keep typing into a
  /// screen that looks fine. The home screen renders this as a banner.
  final ValueNotifier<StorageTrouble?> storageTrouble =
      ValueNotifier<StorageTrouble?>(null);

  void _onStorageTrouble(String kind, String detail) {
    storageTrouble.value = StorageTrouble(kind: kind, detail: detail);
  }

  /// A later write succeeded: a "that save did not go through" banner is now
  /// stale. Load/corrupt banners stay — nothing later makes them untrue.
  void _onStorageWritten() {
    if (storageTrouble.value?.kind == 'save') storageTrouble.value = null;
  }

  /// Pro reported by the store before [load] finished (StoreKit replays
  /// transactions at launch); applied after load so it never saves over a
  /// file we have not read yet.
  bool _proPending = false;

  int _idSeq = 0;

  String _newId(String prefix) {
    _idSeq += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  bool get atProjectLimit => !pro && projects.length >= freeProjects;

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> load() async {
    try {
      final proDoc = await _proFile.read();
      pro = proDoc?['pro'] as bool? ?? false;

      final raw = await _file.read();
      if (raw != null) {
        // Older documents (pre-1.0 dev builds) kept the flag here; carry it
        // over to its own file, or the next manuscript write drops it.
        if (raw['pro'] == true && proDoc?['pro'] != true) {
          pro = true;
          _savePro();
        }
        dailyGoal = (raw['dailyGoal'] as num?)?.toInt() ?? defaultDailyGoal;
        projects
          ..clear()
          ..addAll((raw['projects'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(Project.fromJson));
        final log = raw['dailyLog'];
        if (log is Map) {
          dailyLog.clear();
          log.forEach((k, v) {
            if (k is String && v is num) dailyLog[k] = v.toInt();
          });
        }
      }
    } catch (e) {
      // Valid JSON of the wrong shape (a document from a newer build, say)
      // throws here with `projects` already cleared or half-filled. That is a
      // read failure in every way that matters: writing now would replace the
      // real book with the fragment.
      debugPrint('draftbook load skipped: $e');
      _file.readFailed = true;
      _onStorageTrouble('load', '$e');
    }
    var migrateInlineHistory = false;
    try {
      final hadHistoryFile = await _loadHistory();
      // A pre-1.0 document carried history inline; it only survives the next
      // manuscript write if it reaches the history file first.
      migrateInlineHistory = !hadHistoryFile && _anyInlineHistory();
    } catch (e) {
      debugPrint('draftbook history load skipped: $e');
      _historyFile.readFailed = true;
    }

    loaded = true;
    if (migrateInlineHistory) _saveHistoryIfSafe();
    if (_proPending) {
      _proPending = false;
      pro = true;
      _savePro();
    }
    _notify();
  }

  /// Attach saved versions to the scenes they belong to. A scene that still
  /// carries history inside the manuscript (a document written by an earlier
  /// dev build) keeps it; the history file wins where both exist.
  /// Returns whether a history document existed at all.
  Future<bool> _loadHistory() async {
    final doc = await _historyFile.read();
    final scenes = doc?['scenes'];
    if (scenes is! Map) return doc != null;
    for (final p in projects) {
      for (final c in p.chapters) {
        for (final s in c.scenes) {
          final saved = scenes[s.id];
          if (saved is! List) continue;
          s.history
            ..clear()
            ..addAll(saved
                .whereType<Map<String, dynamic>>()
                .map(SceneSnapshot.fromJson));
        }
      }
    }
    return true;
  }

  bool _anyInlineHistory() => projects.any(
      (p) => p.chapters.any((c) => c.scenes.any((s) => s.history.isNotEmpty)));

  /// Tell listeners, but never in the middle of a frame's build/layout phase.
  ///
  /// The editor saves from `dispose()`, which Flutter runs inside
  /// `BuildOwner.finalizeTree()` with the tree locked; a `setState` from a
  /// listener there throws ("setState() or markNeedsBuild() called when widget
  /// tree was locked"). Release builds strip that assert, so this would have
  /// been a debug-only crash on the most-travelled path in the app: type, then
  /// go back. Deferring to a microtask lands the notification after the frame.
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(notifyListeners);
    } else {
      notifyListeners();
    }
  }

  /// True while writing would be destructive: before the first load, or after
  /// a read that failed for a reason that leaves the real document in place.
  /// In that state the app still works — the writer can read and even type —
  /// but nothing is persisted, so a transient IO error cannot turn into an
  /// empty manuscript on disk. The home screen says so in a banner.
  bool get canPersist => loaded && !_file.readFailed;

  /// Persist atomically (see [JsonFileStore]), coalescing a burst of edits into
  /// one encode + one write. [immediate] skips the delay — used when the app is
  /// going away and there may be no next tick.
  void _save({bool immediate = false}) {
    _notify();
    if (!canPersist) return;
    if (immediate) {
      _saveTimer?.cancel();
      _saveTimer = null;
      _writeManuscript();
      return;
    }
    _saveTimer ??= Timer(const Duration(milliseconds: 600), () {
      _saveTimer = null;
      _writeManuscript();
    });
  }

  void _writeManuscript() {
    _file.write({
      'v': 1,
      'dailyGoal': dailyGoal,
      'dailyLog': dailyLog,
      // Without history: it lives in its own document, see [_historyFile].
      'projects': projects.map((p) => p.toJson()).toList(),
    });
  }

  void _saveHistory() => _saveHistoryIfSafe();

  /// Like [canPersist], for the history document: a history file that exists
  /// but could not be read must not be replaced by the (empty) in-memory
  /// history the moment one scene takes a version.
  void _saveHistoryIfSafe() {
    if (!loaded || _historyFile.readFailed) return;
    _historyFile.write({
      'v': 1,
      'scenes': {
        for (final p in projects)
          for (final c in p.chapters)
            for (final s in c.scenes)
              if (s.history.isNotEmpty)
                s.id: s.history.map((h) => h.toJson()).toList(),
      },
    });
  }

  void _savePro() {
    _proFile.write({'pro': pro});
  }

  /// Write anything outstanding right now. Called when the app is backgrounded
  /// or an editor closes — the two moments after which there may not be a next
  /// frame.
  void saveNow() => _save(immediate: true);

  /// Completes when every queued write has hit the disk. Used by tests and
  /// before the app is torn down.
  Future<void> flush() async {
    if (_saveTimer != null) saveNow();
    await _file.flush();
    await _historyFile.flush();
    await _proFile.flush();
  }

  void unlockPro() {
    if (!loaded) {
      _proPending = true;
      return;
    }
    pro = true;
    _savePro();
    _save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    storageTrouble.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Projects
  // -------------------------------------------------------------------------

  Project? projectById(String? id) {
    if (id == null) return null;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// A new book starts with one chapter and one scene, so the writer lands on
  /// a page they can type into instead of on two more "+" buttons.
  Project addProject({String title = '', int targetWords = 0}) {
    final scene = Scene(id: _newId('scn'));
    final chapter = Chapter(id: _newId('chp'), scenes: [scene]);
    final p = Project(
      id: _newId('prj'),
      title: title.trim(),
      targetWords: targetWords,
      chapters: [chapter],
      lastSceneId: scene.id,
    );
    projects.insert(0, p);
    _save();
    return p;
  }

  void updateProject(Project p,
      {String? title, String? note, int? targetWords}) {
    if (title != null) p.title = title.trim();
    if (note != null) p.note = note.trim();
    if (targetWords != null) p.targetWords = targetWords < 0 ? 0 : targetWords;
    _touch(p);
  }

  void deleteProject(Project p) {
    projects.remove(p);
    _saveHistory();
    _save();
  }

  void _touch(Project p) {
    p.updatedMs = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  // -------------------------------------------------------------------------
  // Chapters & scenes
  // -------------------------------------------------------------------------

  Chapter addChapter(Project p, {String title = ''}) {
    final c = Chapter(id: _newId('chp'), title: title.trim());
    p.chapters.add(c);
    _touch(p);
    return c;
  }

  void renameChapter(Project p, Chapter c, String title) {
    c.title = title.trim();
    _touch(p);
  }

  void toggleChapterCollapsed(Project p, Chapter c) {
    c.collapsed = !c.collapsed;
    _touch(p);
  }

  /// Deletes a chapter and everything in it. The caller is responsible for
  /// confirming first — this is the one destructive action in the app.
  void deleteChapter(Project p, Chapter c) {
    p.chapters.remove(c);
    if (p.chapters.isEmpty) p.chapters.add(Chapter(id: _newId('chp')));
    _saveHistory();
    _touch(p);
  }

  Scene addScene(Project p, Chapter c, {String title = ''}) {
    final s = Scene(id: _newId('scn'), title: title.trim());
    c.scenes.add(s);
    _touch(p);
    return s;
  }

  void updateScene(
    Project p,
    Scene s, {
    String? title,
    String? synopsis,
    SceneStatus? status,
  }) {
    if (title != null) s.title = title.trim();
    if (synopsis != null) s.synopsis = synopsis.trim();
    if (status != null) s.status = status;
    s.updatedMs = DateTime.now().millisecondsSinceEpoch;
    _touch(p);
  }

  void deleteScene(Project p, Chapter c, Scene s) {
    c.scenes.remove(s);
    if (p.lastSceneId == s.id) p.lastSceneId = null;
    // Rewrite the history document so the deleted scene's versions go with it.
    _saveHistory();
    _touch(p);
  }

  /// Move a chapter from [from] to [to]. Both are post-removal indices, which
  /// is what `ReorderableListView.onReorderItem` hands us — the older
  /// `onReorder` callback's off-by-one when dragging downwards is exactly the
  /// bug this signature avoids.
  void reorderChapters(Project p, int from, int to) {
    if (from < 0 || from >= p.chapters.length) return;
    final c = p.chapters.removeAt(from);
    p.chapters.insert(to.clamp(0, p.chapters.length), c);
    _touch(p);
  }

  /// Move a scene within its chapter; see [reorderChapters] for the indices.
  void reorderScenes(Project p, Chapter c, int from, int to) {
    if (from < 0 || from >= c.scenes.length) return;
    final s = c.scenes.removeAt(from);
    c.scenes.insert(to.clamp(0, c.scenes.length), s);
    _touch(p);
  }

  /// Move a scene to another chapter, keeping its text, synopsis and history.
  void moveScene(Project p, Chapter from, Chapter to, Scene s) {
    if (identical(from, to)) return;
    if (!from.scenes.remove(s)) return;
    to.scenes.add(s);
    to.collapsed = false;
    _touch(p);
  }

  /// The scene the writer was last in, so "open the app → keep writing" is two
  /// taps. Null when that scene has since been deleted.
  SceneRef? lastScene(Project p) => findScene(p, p.lastSceneId);

  SceneRef? findScene(Project p, String? sceneId) {
    if (sceneId == null) return null;
    for (var ci = 0; ci < p.chapters.length; ci++) {
      final c = p.chapters[ci];
      for (var si = 0; si < c.scenes.length; si++) {
        if (c.scenes[si].id == sceneId) {
          return SceneRef(
            project: p,
            chapter: c,
            scene: c.scenes[si],
            chapterIndex: ci,
            sceneIndex: si,
          );
        }
      }
    }
    return null;
  }

  /// First scene of the book, used when there is no "last scene" yet.
  SceneRef? firstScene(Project p) {
    for (var ci = 0; ci < p.chapters.length; ci++) {
      if (p.chapters[ci].scenes.isNotEmpty) {
        return SceneRef(
          project: p,
          chapter: p.chapters[ci],
          scene: p.chapters[ci].scenes.first,
          chapterIndex: ci,
          sceneIndex: 0,
        );
      }
    }
    return null;
  }

  void noteSceneOpened(Project p, Scene s) {
    if (p.lastSceneId == s.id) return;
    p.lastSceneId = s.id;
    _save();
  }

  // -------------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------------

  /// Save a scene's body and credit today's writing log with the difference.
  ///
  /// Deletions count as negative words — a day spent cutting 300 words should
  /// not read as 300 written — but a day's total never goes below zero.
  void updateSceneBody(Project p, Scene s, String body, {bool count = true}) {
    if (s.body == body) return;
    final before = s.words; // cached
    final after = countWords(body);

    // A scene written and then wiped inside a single session would otherwise
    // vanish without a trace: it started empty, so no version was ever taken,
    // and the version taken on leaving is refused because the body is now
    // empty. Keep the outgoing text before a big cut lands.
    if (before >= 25 && after * 2 < before) {
      snapshotScene(p, s, note: 'pre-cut');
    }

    final delta = after - before;
    s.body = body;
    s.updatedMs = DateTime.now().millisecondsSinceEpoch;
    if (s.status == SceneStatus.todo && body.trim().isNotEmpty) {
      s.status = SceneStatus.drafting;
    }
    if (count && delta != 0) _logWords(delta);
    _touch(p);
  }

  void _logWords(int delta) {
    final key = dayKey(DateTime.now());
    final next = (dailyLog[key] ?? 0) + delta;
    dailyLog[key] = next < 0 ? 0 : next;
    if (dailyLog.length > maxLogDays) {
      final keys = dailyLog.keys.toList()..sort();
      for (final k in keys.take(dailyLog.length - maxLogDays)) {
        dailyLog.remove(k);
      }
    }
  }

  int get todayWords => dailyLog[dayKey(DateTime.now())] ?? 0;

  /// Consecutive days meeting [dailyGoal], counted back from today. A day that
  /// is still in progress does not break the streak — the run is measured from
  /// yesterday when today's goal has not been met yet.
  int get streakDays {
    if (dailyGoal <= 0) return 0;
    final today = DateTime.now();
    var day = DateTime(today.year, today.month, today.day);
    var n = 0;
    if ((dailyLog[dayKey(day)] ?? 0) >= dailyGoal) {
      n = 1;
    }
    day = _previousDay(day);
    while ((dailyLog[dayKey(day)] ?? 0) >= dailyGoal) {
      n++;
      day = _previousDay(day);
    }
    return n;
  }

  /// The calendar day before [d]. Not `subtract(Duration(days: 1))`: that is 24
  /// absolute hours, so in a zone with daylight saving it skips one day twice a
  /// year and reads its neighbour twice — a streak that silently breaks on the
  /// clock change. `DateTime(y, m, d - 1)` normalises across months and years.
  static DateTime _previousDay(DateTime d) =>
      DateTime(d.year, d.month, d.day - 1);

  /// Words written on each of the last [days] days, oldest first — the bars in
  /// the stats sheet.
  List<int> recentDays(int days) {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        dailyLog[dayKey(DateTime(base.year, base.month, base.day - i))] ?? 0,
    ];
  }

  void setDailyGoal(int words) {
    dailyGoal = words < 0 ? 0 : words;
    _save();
  }

  // -------------------------------------------------------------------------
  // Version history
  // -------------------------------------------------------------------------

  /// Keep a version of [s] as it is now. No-op when the newest snapshot is
  /// already identical, so leaving a scene without typing does not fill the
  /// history with copies.
  bool snapshotScene(Project p, Scene s, {String note = ''}) {
    if (s.body.trim().isEmpty) return false;
    if (s.history.isNotEmpty && s.history.last.body == s.body) return false;
    s.history.add(SceneSnapshot(
      ms: DateTime.now().millisecondsSinceEpoch,
      body: s.body,
      note: note,
    ));
    while (s.history.length > Scene.maxHistory) {
      s.history.removeAt(0);
    }
    _saveHistory();
    _touch(p);
    return true;
  }

  /// Put an older version back as the live text. The text being replaced is
  /// snapshotted first, so restoring is itself undoable — nothing a writer
  /// typed is ever dropped on the floor.
  void restoreSnapshot(Project p, Scene s, SceneSnapshot snap) {
    snapshotScene(p, s, note: 'pre-restore');
    // Not counted towards today: putting back last week's longer draft is not
    // words written today, and the stats screen promises the number is honest.
    updateSceneBody(p, s, snap.body, count: false);
  }

  void deleteSnapshot(Project p, Scene s, SceneSnapshot snap) {
    s.history.remove(snap);
    _saveHistory();
    _touch(p);
  }
}
