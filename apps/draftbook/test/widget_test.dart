import 'dart:io';

import 'package:draftbook/main.dart';
import 'package:draftbook/tool/app_theme.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:draftbook/tool/ui/line_gauge.dart';
import 'package:draftbook/tool/ui/outline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points every JSON store at a throwaway directory. Without this the editor's
/// dispose-time save and the review prompt aim at the host's real documents
/// folder (FakeAsync happens not to deliver the IO today — by accident).
class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('draftbook_widget_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tmp.path);
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // A throwaway directory; leaving it behind must not fail the suite.
    }
  });

  setUp(() {
    // `flutter test` registers the host's Dart-side path_provider, so load()
    // would await real file I/O that FakeAsync never delivers and the home
    // would sit on its spinner forever. Mark the (empty) store loaded up
    // front, and start every test from a clean shelf.
    tool.store.projects.clear();
    tool.store.dailyLog.clear();
    tool.store.pro = false;
    tool.store.loaded = true;
    LineGauge.resetMemory();
  });

  testWidgets('app boots straight onto the page: no app bar, settings in reach',
      (tester) async {
    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    // kb/UIUX规矩.md V1: the first screen is the tool, not an AppBar + gear.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('an empty shelf is a blank page, and one tap starts writing',
      (tester) async {
    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LineGauge), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget, reason: 'the title field, inline');
    expect(find.widgetWithText(FilledButton, 'Start writing'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Night Bus');
    await tester.tap(find.widgetWithText(FilledButton, 'Start writing'));
    await tester.pumpAndSettle();
    // kb F1: first result in one tap — a book exists and the caret is in it.
    expect(tool.store.projects, hasLength(1));
    expect(tool.store.projects.single.title, 'Night Bus');
    expect(find.byType(EditorScreen), findsOneWidget);
  });

  testWidgets('a book shows its page, the line gauge and the way back in',
      (tester) async {
    final p = tool.store.addProject(title: 'Night Bus', targetWords: 1000);
    tool.store.updateSceneBody(
      p,
      tool.store.firstScene(p)!.scene,
      'one two three four five',
    );

    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('of 500 words today'), findsOneWidget);
    expect(find.byType(LineGauge), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Keep writing'), findsOneWidget);
    expect(find.text('Night Bus'), findsWidgets);
    // The page shows the writer's own last words.
    expect(find.textContaining('one two three four five', findRichText: true), findsOneWidget);
  });
  testWidgets('the shelf opens the outline, and the outline opens the editor',
      (tester) async {
    final p = tool.store.addProject(title: 'Night Bus');
    tool.store.addChapter(p, title: 'Departure');

    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Night Bus').last);
    await tester.pumpAndSettle();
    expect(find.byType(OutlineScreen), findsOneWidget);
    expect(find.text('Departure'), findsOneWidget);

    await tester.tap(find.text('Scene 1').first);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    // The always-available formatting bar (PLAN.md 交互铁律 1).
    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.byTooltip('Italic'), findsOneWidget);
  });

  testWidgets('typing in the editor is counted and saved', (tester) async {
    final p = tool.store.addProject(title: 'Night Bus');
    final scene = tool.store.firstScene(p)!.scene;

    await tester.pumpWidget(MaterialApp(
      theme: buildDraftbookTheme(Brightness.light),
      home: EditorScreen(store: tool.store, projectId: p.id, sceneId: scene.id),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'one two three');
    await tester.pump(const Duration(seconds: 1));

    expect(scene.body, 'one two three');
    expect(find.textContaining('3 words', findRichText: true), findsOneWidget);
    expect(tool.store.todayWords, 3);
  });

  testWidgets('typing and then going back neither throws nor loses the text',
      (tester) async {
    // The most-travelled path in the app, and the one that used to throw:
    // leaving the editor saves from dispose(), which runs with the widget tree
    // locked, so the store's notification has to land after the frame.
    final p = tool.store.addProject(title: 'Night Bus');
    final scene = tool.store.firstScene(p)!.scene;

    // The launcher screen listens to the store and calls setState, exactly
    // like the outline and the shelf do underneath a real editor. Without a
    // listener there is nothing for a locked-tree notification to break, and
    // the test passes against the buggy code too.
    var rebuilds = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildDraftbookTheme(Brightness.light),
      home: ListenableBuilder(
        listenable: tool.store,
        builder: (context, _) {
          rebuilds++;
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EditorScreen(
                    store: tool.store,
                    projectId: p.id,
                    sceneId: scene.id,
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          );
        },
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'a sentence worth keeping');
    await tester.pump(const Duration(seconds: 1));

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(scene.body, 'a sentence worth keeping');
    expect(scene.history, isNotEmpty,
        reason: 'the session left a version behind');
    expect(rebuilds, greaterThan(1),
        reason: 'the listener really was notified across the pop');
  });

  testWidgets('a session takes one version at its start, not one per pause',
      (tester) async {
    final p = tool.store.addProject(title: 'Night Bus');
    final scene = tool.store.firstScene(p)!.scene;
    tool.store.updateSceneBody(p, scene, 'the opening line');
    expect(scene.history, isEmpty);

    await tester.pumpWidget(MaterialApp(
      theme: buildDraftbookTheme(Brightness.light),
      home: EditorScreen(store: tool.store, projectId: p.id, sceneId: scene.id),
    ));
    await tester.pump();

    // Three bursts of typing, each followed by a pause longer than the
    // autosave debounce — the cadence that used to add a version per pause.
    for (final text in [
      'the opening line, then',
      'the opening line, then more',
      'the opening line, then more still',
    ]) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(seconds: 1));
    }

    expect(scene.body, 'the opening line, then more still');
    expect(scene.history.map((h) => h.body).toList(), ['the opening line'],
        reason: 'only the text the session started with is kept mid-session');
  });

  testWidgets('the free tier offers Pro instead of a second book',
      (tester) async {
    tool.store.addProject(title: 'Night Bus');

    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byTooltip('Your books'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New book'));
    await tester.pumpAndSettle();
    expect(find.text('Draftbook Pro'), findsOneWidget);
    // The gate explains itself, and nothing is charged from here.
    expect(find.textContaining('free version keeps one book'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
  });
}
