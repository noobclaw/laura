import 'package:astropile/tool/app_theme.dart';
import 'package:astropile/tool/engine/stack.dart';
import 'package:astropile/tool/models.dart';
import 'package:astropile/tool/store.dart';
import 'package:astropile/tool/ui/frames_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frame list is where every pre-run decision is made, and where a
/// pre-submission audit found a crash that 31 engine tests could not see:
/// the screen read a `late` field while it was still computing it, so the
/// app died the moment anyone picked photos. These tests pump the real
/// widget, which is the only thing that would have caught it.
SourceFrame frame(
  String id, {
  int width = 4000,
  int height = 3000,
  int? iso = 3200,
  double? shutter = 4,
}) =>
    SourceFrame(
      id: id,
      path: '/tmp/$id.jpg',
      name: '$id.jpg',
      bytes: 5 << 20,
      width: width,
      height: height,
      format: SourceFormat.jpeg,
      iso: iso,
      exposureSeconds: shutter,
    );

Future<void> pump(WidgetTester tester, AstroStore store, List<SourceFrame> frames) async {
  // A tall surface: the frame rows sit below the summary and the two option
  // cards, and a lazy ListView never builds what a 600 px viewport cannot
  // show — the rows under test would simply not exist.
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAstroTheme(Brightness.light),
    home: FramesScreen(store: store, frames: frames),
  ));
  await tester.pump();
}

void main() {
  testWidgets('opens with a uniform burst and offers to stack all of it',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [frame('a'), frame('b'), frame('c')]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Stack 3 frames'), findsOneWidget);
    // Every checkbox ticked, and the first frame is the reference.
    for (final cb in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(cb.value, isTrue);
    }
    expect(find.text('REFERENCE'), findsOneWidget);
  });

  testWidgets('a frame of a different size is disabled and says why',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [
      frame('a'),
      frame('b'),
      frame('odd', width: 3000, height: 4000),
    ]);

    expect(tester.takeException(), isNull);
    // The odd one out is unticked and cannot be re-ticked.
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.where((b) => b.value == false).length, 1);
    expect(boxes.where((b) => b.onChanged == null).length, 1);
    expect(find.textContaining('does not match the rest'), findsOneWidget);
    expect(find.textContaining('Stack 2 frames'), findsOneWidget);
  });

  testWidgets('a frame shot at a different exposure is flagged but usable',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [
      frame('a'),
      frame('b'),
      frame('bright', iso: 100, shutter: 0.008),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('different exposure settings'), findsOneWidget);
    // Flagged, not excluded.
    expect(find.textContaining('Stack 3 frames'), findsOneWidget);
  });

  testWidgets('the free tier keeps the first six and unticks the rest',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [for (var i = 0; i < 9; i++) frame('f$i')]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Stack $kFreeFrameLimit frames'), findsOneWidget);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.where((b) => b.value == true).length, kFreeFrameLimit);
  });

  testWidgets('Pro raises the cap without any other change', (tester) async {
    final store = AstroStore()
      ..loaded = true
      ..pro = true;
    await pump(tester, store, [for (var i = 0; i < 9; i++) frame('f$i')]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Stack 9 frames'), findsOneWidget);
  });

  testWidgets('two frames is the floor for the stack button', (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [frame('a'), frame('b')]);

    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNotNull);

    // Untick one: one frame is not a stack.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    final after = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(after.onPressed, isNull);
  });

  testWidgets('frames with no EXIF do not become exposure outliers',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [
      frame('a', iso: null, shutter: null),
      frame('b', iso: null, shutter: null),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('different exposure settings'), findsNothing);
  });

  // ---- M2: the two new modes and the calibration card. ----

  testWidgets('all four combine modes are offered', (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [frame('a'), frame('b')]);

    expect(tester.takeException(), isNull);
    for (final label in ['Mean', 'Median', 'Kappa-sigma', 'Star trails']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('star trails is free; kappa-sigma is not', (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [frame('a'), frame('b')]);

    // Trails takes effect immediately for a free user...
    await tester.tap(find.text('Star trails'));
    await tester.pumpAndSettle();
    expect(store.settings.mode.isTrails, isTrue);
    expect(find.textContaining('skips star alignment'), findsOneWidget);

    // ...while kappa-sigma opens the unlock sheet and leaves the mode alone.
    await tester.tap(find.text('Kappa-sigma'));
    await tester.pumpAndSettle();
    expect(store.settings.mode, isNot(StackMode.kappaSigma));
    expect(find.text('AstroPile Pro'), findsOneWidget);
  });

  testWidgets('a Pro user gets kappa-sigma without a paywall', (tester) async {
    final store = AstroStore()
      ..loaded = true
      ..pro = true;
    await pump(tester, store, [frame('a'), frame('b')]);

    await tester.tap(find.text('Kappa-sigma'));
    await tester.pumpAndSettle();
    expect(store.settings.mode, StackMode.kappaSigma);
    expect(find.text('AstroPile Pro'), findsNothing);
  });

  testWidgets('calibration is offered but gated, and never silently on',
      (tester) async {
    final store = AstroStore()..loaded = true;
    await pump(tester, store, [frame('a'), frame('b')]);

    expect(find.text('Calibration (optional)'), findsOneWidget);
    expect(find.text('Dark frames'), findsOneWidget);
    expect(find.text('Flat frames'), findsOneWidget);
    // The free tier sees the card with a PRO badge; tapping Pick explains
    // rather than opening a picker that would go nowhere.
    expect(find.text('PRO'), findsOneWidget);
    await tester.tap(find.text('Pick').first);
    await tester.pumpAndSettle();
    expect(find.text('AstroPile Pro'), findsOneWidget);
  });
}
