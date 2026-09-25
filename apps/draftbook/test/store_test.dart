import 'dart:io';

import 'package:draftbook/tool/models.dart';
import 'package:draftbook/tool/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points `JsonFileStore` at a throwaway directory so the tests never touch the
/// host's real documents folder.
class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  // The store defers its notifications out of the frame's build phase, which
  // asks the SchedulerBinding what phase it is in; plain `test()` cases have no
  // binding until this runs.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final opened = <DraftbookStore>[];

  setUp(() async {
    opened.clear();
    tmp = await Directory.systemTemp.createTemp('draftbook_store_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tmp.path);
  });

  tearDown(() async {
    // Let every queued atomic write finish before the directory goes away:
    // on Windows a rename still in flight holds the file open.
    for (final s in opened) {
      await s.flush();
    }
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // A throwaway directory in the system temp folder; if the OS is still
      // holding it, leaving it behind must not fail the test.
    }
  });

  Future<DraftbookStore> freshStore() async {
    final s = DraftbookStore();
    opened.add(s);
    await s.load();
    return s;
  }

  test('a new book arrives with somewhere to type', () async {
    final s = await freshStore();
    final p = s.addProject(title: 'Night Bus');
    expect(p.chapters, hasLength(1));
    expect(p.chapters.first.scenes, hasLength(1));
    expect(s.firstScene(p)?.scene.id, p.lastSceneId);
  });

  test('the free tier keeps one book and Pro lifts the cap', () async {
    final s = await freshStore();
    expect(s.atProjectLimit, isFalse);
    s.addProject(title: 'One');
    expect(s.atProjectLimit, isTrue);
    s.unlockPro();
    expect(s.atProjectLimit, isFalse);
    s.addProject(title: 'Two');
    expect(s.projects, hasLength(2));
  });

  test('everything survives a reload', () async {
    final s = await freshStore();
    final p = s.addProject(title: 'Night Bus', targetWords: 50000);
    final scene = s.firstScene(p)!.scene;
    s.updateSceneBody(p, scene, 'the first sentence');
    s.snapshotScene(p, scene);
    s.updateSceneBody(p, scene, 'the first sentence, rewritten');
    await s.flush();

    final again = DraftbookStore();
    opened.add(again);
    await again.load();
    expect(again.projects, hasLength(1));
    final back = again.projects.first;
    expect(back.title, 'Night Bus');
    expect(back.targetWords, 50000);
    final backScene = again.firstScene(back)!.scene;
    expect(backScene.body, 'the first sentence, rewritten');
    expect(backScene.history, hasLength(1));
    expect(backScene.history.first.body, 'the first sentence');
  });

  test('scenes reorder inside a chapter and move between chapters', () async {
    final s = await freshStore();
    final p = s.addProject();
    final c1 = p.chapters.first;
    c1.scenes.first.title = 'A';
    final b = s.addScene(p, c1, title: 'B');
    s.addScene(p, c1, title: 'C');
    expect(c1.scenes.map((e) => e.title), ['A', 'B', 'C']);

    // Drag the first scene to the end (post-removal index, as the framework
    // hands it to us).
    s.reorderScenes(p, c1, 0, 2);
    expect(c1.scenes.map((e) => e.title), ['B', 'C', 'A']);

    final c2 = s.addChapter(p, title: 'Two');
    s.moveScene(p, c1, c2, b);
    expect(c1.scenes.map((e) => e.title), ['C', 'A']);
    expect(c2.scenes.map((e) => e.title), ['B']);

    s.reorderChapters(p, 1, 0);
    expect(p.chapters.first.title, 'Two');
  });

  test('deleting the last chapter leaves one empty chapter behind', () async {
    final s = await freshStore();
    final p = s.addProject();
    s.deleteChapter(p, p.chapters.first);
    expect(p.chapters, hasLength(1));
    expect(p.chapters.first.scenes, isEmpty);
  });

  test('the daily log follows what was written, and cuts subtract', () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;

    s.updateSceneBody(p, scene, 'one two three four five');
    expect(s.todayWords, 5);
    s.updateSceneBody(p, scene, 'one two');
    expect(s.todayWords, 2, reason: 'three words cut');
    s.updateSceneBody(p, scene, '');
    expect(s.todayWords, 0, reason: 'a day total never goes negative');
  });

  test('a streak counts back from today and survives an unfinished today',
      () async {
    final s = await freshStore();
    s.setDailyGoal(100);
    final today = DateTime.now();
    DateTime back(int n) => today.subtract(Duration(days: n));

    s.dailyLog[dayKey(back(1))] = 120;
    s.dailyLog[dayKey(back(2))] = 300;
    s.dailyLog[dayKey(back(3))] = 40; // missed
    expect(s.streakDays, 2, reason: 'today not written yet, run is 2 days');

    s.dailyLog[dayKey(today)] = 150;
    expect(s.streakDays, 3);
  });

  test('version history caps, refuses duplicates and restores reversibly',
      () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;

    s.updateSceneBody(p, scene, 'first draft');
    expect(s.snapshotScene(p, scene), isTrue);
    expect(s.snapshotScene(p, scene), isFalse, reason: 'nothing changed');

    for (var i = 0; i < Scene.maxHistory + 5; i++) {
      s.updateSceneBody(p, scene, 'draft $i');
      s.snapshotScene(p, scene);
    }
    expect(scene.history.length, Scene.maxHistory);

    final old = scene.history.first;
    final current = scene.body;
    s.restoreSnapshot(p, scene, old);
    expect(scene.body, old.body);
    expect(
      scene.history.last.body,
      current,
      reason: 'the replaced text is kept, so a restore can be undone',
    );
  });

  test('an empty scene is not worth a version', () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;
    expect(s.snapshotScene(p, scene), isFalse);
  });

  test('writing into a fresh scene moves it out of "to write"', () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;
    expect(scene.status, SceneStatus.todo);
    s.updateSceneBody(p, scene, 'something');
    expect(scene.status, SceneStatus.drafting);
  });

  test('a Pro unlock reported before the load lands afterwards', () async {
    final s = DraftbookStore();
    opened.add(s);
    s.unlockPro(); // StoreKit replays transactions before load() finishes
    expect(s.pro, isFalse);
    await s.load();
    expect(s.pro, isTrue);
    await s.flush();

    final again = DraftbookStore();
    opened.add(again);
    await again.load();
    expect(again.pro, isTrue);
  });

  test('a read that fails is never treated as an empty manuscript', () async {
    // Not a parse failure (that one is quarantined and starting fresh is
    // right): bytes that are not valid UTF-8, so `readAsString` throws and the
    // real document is still sitting there.
    final f = File('${tmp.path}/draftbook.json');
    await f.writeAsBytes([0xff, 0xfe, 0xfd, 0x00, 0x41]);
    final before = await f.readAsBytes();

    final s = DraftbookStore();
    opened.add(s);
    await s.load();

    expect(s.loaded, isTrue, reason: 'the app still runs');
    expect(s.canPersist, isFalse, reason: 'but it must not write');
    expect(s.storageTrouble.value?.kind, 'load', reason: 'and it must say so');

    // The user types anyway; nothing may reach the disk.
    s.addProject(title: 'Night Bus');
    s.saveNow();
    await s.flush();
    expect(await f.readAsBytes(), before,
        reason: 'the untouched document must still be on disk');
  });

  test('a history file that cannot be read is never overwritten', () async {
    final f = File('${tmp.path}/draftbook_history.json');
    await f.writeAsBytes([0xff, 0xfe, 0xfd, 0x00, 0x41]);
    final before = await f.readAsBytes();

    final s = DraftbookStore();
    opened.add(s);
    await s.load();
    expect(s.canPersist, isTrue, reason: 'the manuscript itself is fine');

    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;
    s.updateSceneBody(p, scene, 'a new version');
    s.snapshotScene(p, scene);
    await s.flush();
    expect(await f.readAsBytes(), before,
        reason: 'the unreadable history must still be on disk, untouched');
  });

  test('a manuscript of the wrong shape is a failed read, not an empty book',
      () async {
    final f = File('${tmp.path}/draftbook.json');
    await f.writeAsString('{"projects": {"not": "a list"}}');
    final before = await f.readAsString();

    final s = DraftbookStore();
    opened.add(s);
    await s.load();
    expect(s.canPersist, isFalse);
    expect(s.storageTrouble.value?.kind, 'load');

    s.addProject(title: 'Night Bus');
    s.saveNow();
    await s.flush();
    expect(await f.readAsString(), before);
  });

  test('a big cut keeps the text it removed', () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;
    final draft = List.generate(60, (i) => 'word$i').join(' ');

    s.updateSceneBody(p, scene, draft);
    expect(scene.history, isEmpty, reason: 'nothing has been lost yet');

    // Select all, type one character.
    s.updateSceneBody(p, scene, 'x');
    expect(scene.body, 'x');
    expect(scene.history.map((h) => h.body), contains(draft),
        reason: 'the 60 words must be recoverable');
  });

  test('restoring an older version does not count as writing today', () async {
    final s = await freshStore();
    final p = s.addProject();
    final scene = s.firstScene(p)!.scene;

    s.updateSceneBody(p, scene, 'one two three four five six');
    s.snapshotScene(p, scene);
    s.updateSceneBody(p, scene, 'one two');
    final todayBefore = s.todayWords;

    s.restoreSnapshot(p, scene, scene.history.first);
    expect(scene.body, 'one two three four five six');
    expect(s.todayWords, todayBefore,
        reason: 'putting last week’s words back is not writing them today');
  });

  test('a damaged manuscript does not revoke Pro', () async {
    await File('${tmp.path}/draftbook_pro.json').writeAsString('{"pro":true}');
    await File('${tmp.path}/draftbook.json').writeAsString('{not json');
    final s = DraftbookStore();
    opened.add(s);
    await s.load();
    expect(s.pro, isTrue, reason: 'the purchase lives in its own document');
    expect(s.projects, isEmpty);
  });

  test('version history is kept out of the manuscript document', () async {
    final s = await freshStore();
    final p = s.addProject(title: 'Night Bus');
    final scene = s.firstScene(p)!.scene;
    s.updateSceneBody(p, scene, 'the first sentence');
    s.snapshotScene(p, scene);
    s.updateSceneBody(p, scene, 'the second sentence');
    await s.flush();

    final manuscript = await File('${tmp.path}/draftbook.json').readAsString();
    expect(manuscript, contains('the second sentence'));
    expect(manuscript, isNot(contains('the first sentence')),
        reason: 'the hot path must not re-encode every saved version');
    final history =
        await File('${tmp.path}/draftbook_history.json').readAsString();
    expect(history, contains('the first sentence'));
  });

  test('a damaged document does not cost the writer their Pro flag or crash',
      () async {
    await File('${tmp.path}/draftbook.json').writeAsString('{not json');
    final s = DraftbookStore();
    opened.add(s);
    await s.load();
    expect(s.loaded, isTrue);
    expect(s.projects, isEmpty);
    // JsonFileStore keeps the damaged bytes aside rather than overwriting.
    expect(
      Directory(tmp.path)
          .listSync()
          .any((f) => f.path.contains('draftbook.json.corrupt-')),
      isTrue,
    );
  });

  group('undo instead of confirm (kb F4)', () {
    test('a deleted book comes back whole, history and all, and survives a reload', () async {
      final s = await freshStore();
      final p = s.addProject(title: 'Night Bus');
      final scene = s.firstScene(p)!.scene;
      s.updateSceneBody(p, scene, 'first draft');
      s.snapshotScene(p, scene);
      s.updateSceneBody(p, scene, 'second draft');
      final index = s.projects.indexOf(p);

      s.deleteProject(p);
      expect(s.projects, isEmpty);
      s.reinsertProject(p, index);
      await s.flush();

      final again = await freshStore();
      expect(again.projects.single.title, 'Night Bus');
      final back = again.firstScene(again.projects.single)!.scene;
      expect(back.body, 'second draft');
      expect(back.history.map((h) => h.body), ['first draft']);
    });

    test('undoing the only chapter removes the empty stand-in', () async {
      final s = await freshStore();
      final p = s.addProject(title: 'Night Bus');
      final only = p.chapters.single;
      s.deleteChapter(p, only);
      final standIn = p.chapters.single;
      expect(identical(standIn, only), isFalse);

      s.reinsertChapter(p, only, 0, placeholder: standIn);
      expect(p.chapters, [only]);
    });

    test('a deleted scene returns to its place and is still the last one open', () async {
      final s = await freshStore();
      final p = s.addProject(title: 'Night Bus');
      final c = p.chapters.single;
      final a = c.scenes.single;
      final b = s.addScene(p, c, title: 'B');
      s.noteSceneOpened(p, a);

      s.deleteScene(p, c, a);
      expect(p.lastSceneId, isNull);
      expect(s.reinsertScene(p, c, a, 0, wasLast: true), isTrue);
      expect(c.scenes, [a, b]);
      expect(p.lastSceneId, a.id);
    });

    test('a restore can be taken back without losing either text', () async {
      final s = await freshStore();
      final p = s.addProject(title: 'Night Bus');
      final scene = s.firstScene(p)!.scene;
      s.updateSceneBody(p, scene, 'old words');
      s.snapshotScene(p, scene);
      final old = scene.history.single;
      s.updateSceneBody(p, scene, 'new words');
      final todayBefore = s.todayWords;

      s.restoreSnapshot(p, scene, old);
      expect(scene.body, 'old words');
      s.undoRestore(p, scene, 'new words');
      expect(scene.body, 'new words');
      expect(scene.history.map((h) => h.body), containsAll(['old words', 'new words']));
      expect(s.todayWords, todayBefore, reason: 'restoring is not writing');
    });

    test('a deleted version goes back where it was', () async {
      final s = await freshStore();
      final p = s.addProject(title: 'Night Bus');
      final scene = s.firstScene(p)!.scene;
      for (final body in ['one', 'two', 'three']) {
        s.updateSceneBody(p, scene, body);
        s.snapshotScene(p, scene);
      }
      final middle = scene.history[1];
      s.deleteSnapshot(p, scene, middle);
      s.reinsertSnapshot(p, scene, middle, 1);
      expect(scene.history.map((h) => h.body), ['one', 'two', 'three']);
    });
  });
}