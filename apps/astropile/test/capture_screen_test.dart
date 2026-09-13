import 'package:astropile/tool/app_theme.dart';
import 'package:astropile/tool/store.dart';
import 'package:astropile/tool/ui/capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capture screen is the one screen the CI smoke shot cannot reach — it
/// needs a camera — so without these it would ship having never been rendered
/// anywhere.
///
/// In a test binding `availableCameras()` neither returns nor throws, so the
/// preview sits on its spinner forever. That is why nothing here uses
/// `pumpAndSettle`: an indefinite progress indicator never settles, and a
/// test that waits for one is a test that hangs. Pumping fixed frames is both
/// what works and what mirrors the real "camera is taking its time" state.
Future<void> pump(WidgetTester tester, AstroStore store) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAstroTheme(Brightness.light),
    home: CaptureScreen(store: store),
  ));
  await settle(tester);
}

/// Advance far enough for transitions to finish, without waiting for the
/// preview spinner that never will.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Tap the chip itself rather than its label: the label is a [Text] inside a
/// [Row] inside the chip, and hit-testing it directly logs a missed-tap
/// warning that would bury a real one.
Finder chip(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip));

void main() {
  testWidgets('renders with the camera still opening, and stays honest',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store);

    expect(tester.takeException(), isNull);
    // The controls are usable while the preview is still coming up...
    expect(find.text('How many frames'), findsOneWidget);
    expect(find.text('Start the burst'), findsOneWidget);
    // ...and the one thing this screen must never imply is denied in place.
    expect(find.textContaining('It cannot set a long exposure'), findsOneWidget);
    // No camera yet, so the preview is a spinner rather than a black hole.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('keeping the originals is on by default', (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store);

    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.value, isTrue,
        reason: 'a burst the user shot must not be thrown away silently');
  });

  testWidgets('the burst cannot start before the camera is open',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store);

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNull);
  });

  testWidgets('every burst length is offered, the ones over the limit locked',
      (tester) async {
    final store = AstroStore()..loaded = true; // free tier: frameLimit 6
    await pump(tester, store);

    for (final n in kBurstCounts) {
      expect(find.text('$n'), findsOneWidget, reason: '$n');
    }
    // 8 is over the free limit: it opens the unlock sheet rather than
    // silently changing the count, and rather than not being there at all.
    await tester.tap(chip('8'));
    await settle(tester);
    expect(find.text('AstroPile Pro'), findsOneWidget);
    expect(find.textContaining('all 4 frames are shot'), findsOneWidget);
  });

  testWidgets('a Pro user picks 32 without a paywall', (tester) async {
    final store = AstroStore()
      ..loaded = true
      ..pro = true;
    await pump(tester, store);

    await tester.tap(chip('32'));
    await settle(tester);
    expect(find.text('AstroPile Pro'), findsNothing);
    expect(find.textContaining('all 32 frames are shot'), findsOneWidget);
  });
}
