import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/main.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/brand.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';

void main() {
  testWidgets('the library boots with its live bench and examples',
      (tester) async {
    await tester.pumpWidget(const OhmBenchApp());
    await tester.pump(const Duration(milliseconds: 300));

    // The first screen is the bench: no app bar, the wordmark sits on it.
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Draw it. Run it.'), findsOneWidget);
    expect(find.text('Your first circuit lands here'), findsOneWidget);
    // One verb for one action: the dock and the empty state both say it.
    expect(find.text('New circuit'), findsNWidgets(2));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
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
    await tester.tap(find.byKey(const ValueKey('run-button')));
    // The solve runs on another isolate; give it real time.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        find.byWidgetPredicate(
            (w) => w is BenchGlyph && w.kind == GlyphKind.stop),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an example opened from the library is already running (F1)',
      (tester) async {
    final store = ProjectStore();
    final project = store.scratch('RC', kExamples[1].build());
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(store: store, project: project, autoRun: true),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1500)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        find.byWidgetPredicate(
            (w) => w is BenchGlyph && w.kind == GlyphKind.stop),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
