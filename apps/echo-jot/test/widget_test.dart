import 'dart:io';

import 'package:echo_jot/main.dart';
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
    // The list is lazy: assert it rendered cards, not how many fit the viewport.
    expect(find.byType(NoteCard), findsWidgets);
  });
}
