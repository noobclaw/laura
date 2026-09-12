import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autosnore/tool/app_theme.dart';
import 'package:autosnore/tool/home_screen.dart';
import 'package:autosnore/tool/models.dart';
import 'package:autosnore/tool/store.dart';

/// Renders the home with the store already "loaded" (no plugin round-trip)
/// so the breathing-wave hero, its ripple rings and the animated history list
/// actually paint a few frames under test.
void main() {
  SleepSession night(int day) => SleepSession(
        id: 'night-$day',
        startMs: DateTime(2026, 9, day, 23).millisecondsSinceEpoch,
        endMs: DateTime(2026, 9, day + 1, 6).millisecondsSinceEpoch,
        events: const [
          SnoreEvent(startMs: 0, durationMs: 1200, peakDb: -24, avgDb: -28),
        ],
      );

  Widget app(AutoSnoreStore store) => MaterialApp(
        theme: buildNightTheme(),
        home: Scaffold(body: HomeScreen(store: store)),
      );

  testWidgets('hero paints and breathes without errors', (tester) async {
    final store = AutoSnoreStore()..loaded = true;
    await tester.pumpWidget(app(store));
    // A few frames of the 4 s breath cycle: the painters must not throw.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new night animates into the history list', (tester) async {
    final store = AutoSnoreStore()
      ..loaded = true
      ..sessions.add(night(1));
    await tester.pumpWidget(app(store));
    await tester.pump();
    expect(find.byType(AnimatedList), findsOneWidget);
    // The hero's sub-line also quotes the last night's date ("Last 09/01 …"),
    // so the history assertions are scoped to the list itself.
    Finder inList(String date) => find.descendant(
          of: find.byType(AnimatedList),
          matching: find.textContaining(date),
        );
    expect(inList('09/01'), findsOneWidget);

    store.addSession(night(2));
    await tester.pump();
    // Mid-entrance: the new tile exists and the slide is still running.
    await tester.pump(const Duration(milliseconds: 100));
    expect(inList('09/02'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(inList('09/01'), findsOneWidget);
    expect(inList('09/02'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion holds the hero still', (tester) async {
    final store = AutoSnoreStore()..loaded = true;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: app(store),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
