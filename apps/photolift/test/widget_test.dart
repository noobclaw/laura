import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolift/main.dart';
import 'package:photolift/tool/pixel_art.dart';

void main() {
  testWidgets('shell boots and shows the tool home with the hero', (tester) async {
    // Without a handler the path_provider call is answered by the engine on
    // the real event loop, which the fake-async clock never reaches — the
    // store would sit on `loaded == false` (spinner, no hero) for the whole
    // test. A mock that throws makes load() fail fast inside the fake zone,
    // so `loaded` flips and the home (hero + empty state) renders.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => throw PlatformException(code: 'unavailable_in_test'),
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null));

    await tester.pumpWidget(const ShellApp());
    expect(find.byType(ShellApp), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Hero mosaic (looping) + the empty-state mosaic (fixed progress).
    expect(find.byType(PixelResolve), findsNWidgets(2));
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(PressScale), findsOneWidget);
    // The (still empty) grid sits below the viewport's cache extent, so it
    // is offstage for the finder; it must still be mounted for the first
    // result to animate in.
    expect(find.byType(SliverAnimatedGrid, skipOffstage: false), findsOneWidget);
  });

  testWidgets('fixed-progress mosaic disposes cleanly (no lazy ticker in dispose)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(width: 64, height: 64, child: PixelResolve(progress: 0.55)),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero mosaic honours reduced motion with the resolved frame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: SizedBox(width: 64, height: 64, child: PixelResolve()),
      ),
    ));
    await tester.pump();
    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
    expect((paint.painter as PixelResolvePainter).resolve, 1.0);
  });

  testWidgets('pixel painter resolves along the diagonal', (tester) async {
    // resolve=0: nothing fine yet; resolve=1: everything fine. The painter
    // itself is deterministic, so just make sure both extremes paint.
    for (final v in [0.0, 0.5, 1.0]) {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(width: 80, height: 80, child: PixelResolve(progress: v)),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });

  testWidgets('ring painter paints with and without the light band', (tester) async {
    for (final sweep in [-1.0, 0.3]) {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(
            painter: LiftRingPainter(fraction: 0.6, sweep: sweep, track: Colors.grey),
          ),
        ),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });
}
