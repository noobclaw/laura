import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/main.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';

void main() {
  testWidgets('the library boots with its live bench and examples',
      (tester) async {
    await tester.pumpWidget(const OhmBenchApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('OhmBench'), findsOneWidget);
    expect(find.text('Draw it. Run it.'), findsOneWidget);
    expect(find.text('No circuits yet'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Voltage divider'), findsOneWidget);
    // Animated scene: never pumpAndSettle, just advance a few frames.
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor opens an example and runs it', (tester) async {
    final store = ProjectStore();
    final project = store.create('RC', kExamples[1].build());
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(store: store, project: project),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('RC'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    // The solve runs on another isolate; give it real time.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
