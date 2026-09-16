import 'package:draftbook/main.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:draftbook/tool/ui/ink_mark.dart';
import 'package:draftbook/tool/ui/outline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // `flutter test` registers the host's Dart-side path_provider, so load()
    // would await real file I/O that FakeAsync never delivers and the home
    // would sit on its spinner forever. Mark the (empty) store loaded up
    // front, and start every test from a clean shelf.
    tool.store.projects.clear();
    tool.store.dailyLog.clear();
    tool.store.pro = false;
    tool.store.loaded = true;
  });

  testWidgets('app boots and shows its title bar', (tester) async {
    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    // Under `flutter test` the app boots in the 'en' locale.
    expect(find.widgetWithText(AppBar, 'Draftbook'), findsOneWidget);
  });

  testWidgets('an empty shelf shows the mark, the pitch and a way in',
      (tester) async {
    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DraftbookMark), findsOneWidget);
    expect(find.text('Start your first book'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New book'), findsOneWidget);
  });

  testWidgets('a book shows the hero, the ink stroke and the shelf',
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

    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(AnimatedInkStroke), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Keep writing'), findsOneWidget);
    expect(find.text('Night Bus'), findsWidgets);
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
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(find.byIcon(Icons.format_italic), findsOneWidget);
  });

  testWidgets('typing in the editor is counted and saved', (tester) async {
    final p = tool.store.addProject(title: 'Night Bus');
    final scene = tool.store.firstScene(p)!.scene;

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(store: tool.store, projectId: p.id, sceneId: scene.id),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'one two three');
    await tester.pump(const Duration(seconds: 1));

    expect(scene.body, 'one two three');
    expect(find.text('3 words'), findsOneWidget);
    expect(tool.store.todayWords, 3);
  });

  testWidgets('typing and then going back neither throws nor loses the text',
      (tester) async {
    // The most-travelled path in the app, and the one that used to throw:
    // leaving the editor saves from dispose(), which runs with the widget tree
    // locked, so the store's notification has to land after the frame.
    final p = tool.store.addProject(title: 'Night Bus');
    final scene = tool.store.firstScene(p)!.scene;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
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
        ),
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
  });

  testWidgets('the free tier offers Pro instead of a second book',
      (tester) async {
    tool.store.addProject(title: 'Night Bus');

    await tester.pumpWidget(const DraftbookApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New book'));
    await tester.pumpAndSettle();
    expect(find.text('Draftbook Pro'), findsOneWidget);
    // The gate explains itself, and nothing is charged from here.
    expect(find.textContaining('free version keeps one book'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
  });
}
