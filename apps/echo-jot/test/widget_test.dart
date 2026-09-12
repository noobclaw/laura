import 'dart:io';

import 'package:echo_jot/main.dart';
import 'package:echo_jot/tool/dictation_engine.dart';
import 'package:echo_jot/tool/home_page.dart';
import 'package:echo_jot/tool/note.dart';
import 'package:echo_jot/tool/ui_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// NB: never `await` real file I/O inside `testWidgets` — the fake-async clock
/// does not complete dart:io futures and the test hangs until the timeout. These
/// tests build the store with a path only; nothing here writes to disk.
NoteStore storeWith(List<Note> notes) =>
    NoteStore.forTest(File('${Directory.systemTemp.path}/echojot_widget.json'),
        notes);

void main() {
  testWidgets('app boots without crashing', (tester) async {
    await tester.pumpWidget(const EchoJotApp());
    await tester.pump();
    expect(find.byType(EchoJotApp), findsOneWidget);
  });

  testWidgets('empty timeline shows the guidance state and the mic hero',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EchoJotHome(store: storeWith([]))),
    ));
    await tester.pump();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(MicButton), findsOneWidget);
    // Nothing to search yet, so the search field stays out of the way.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('hero shows the active engine and follows the preference',
      (tester) async {
    DictationEnginePref.current.value = DictationEngine.system;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EchoJotHome(store: storeWith([]))),
    ));
    await tester.pump();

    expect(find.text(DictationEnginePref.label(DictationEngine.system)),
        findsOneWidget);
    expect(find.text(DictationEnginePref.label(DictationEngine.whisper)),
        findsNothing);

    // Changing the preference (settings page / banner button) must re-label
    // the chip without any controller activity.
    DictationEnginePref.current.value = DictationEngine.whisper;
    await tester.pump();
    expect(find.text(DictationEnginePref.label(DictationEngine.whisper)),
        findsOneWidget);
    DictationEnginePref.current.value = DictationEngine.system;
  });

  testWidgets('engine picker lists both engines', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EchoJotHome(store: storeWith([]))),
    ));
    await tester.pump();
    await tester.tap(find.text(DictationEnginePref.label(DictationEngine.system)));
    // Not pumpAndSettle: the hero's sound field breathes indefinitely while
    // idle, so the tree never "settles" — pump past the sheet's open animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(DictationEnginePref.label(DictationEngine.whisper)),
        findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('notes render as cards with duration and length chips',
      (tester) async {
    final store = storeWith([
      Note(
        id: '1',
        createdAt: DateTime.now(),
        durationMs: 64000,
        text: 'Buy milk. Call the dentist.',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EchoJotHome(store: store)),
    ));
    await tester.pump();

    expect(find.byType(NoteCard), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget); // card title
    expect(find.text('1:04'), findsOneWidget); // duration chip
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('search field appears once there are several notes',
      (tester) async {
    final store = storeWith([
      for (var i = 0; i < 6; i++)
        Note(
          id: '$i',
          createdAt: DateTime.now().subtract(Duration(minutes: i)),
          durationMs: 5000,
          text: 'note number $i',
        ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: EchoJotHome(store: store)),
    ));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    // Nothing in the body may overflow at 800x600 — the timeline scrolls
    // under the fixed hero panel instead (an overflow throws and fails here).
    expect(tester.takeException(), isNull);
    // The list is lazy and, in the test environment, the "no on-device
    // recognizer" banner sits above it (the recognizer cannot be probed here),
    // which at 600px parks the first card just below the fold: scroll the
    // timeline and assert cards rendered, not how many fit the viewport.
    await tester.scrollUntilVisible(
      find.byType(NoteCard),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(NoteCard), findsWidgets);
  });
}
