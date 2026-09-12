import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autosnore/tool/app_theme.dart';
import 'package:autosnore/tool/recording_screen.dart';

/// Drives the live recording view with a fake source (no microphone, no
/// plugin channels) so its layout and power behaviour can be pinned down.
class _FakeSource extends ChangeNotifier implements LiveRecordingSource {
  @override
  double level = 0.3;
  @override
  bool stalled = false;
  @override
  int elapsedMs = 5 * 3600 * 1000 + 47 * 60 * 1000;
  @override
  int eventCount = 128;
  @override
  double currentDb = -31;
}

void main() {
  Widget app(_FakeSource src, {MediaQueryData? mq, VoidCallback? onStop}) {
    final Widget page = MaterialApp(
      theme: buildNightTheme(),
      home: Scaffold(
        body: SafeArea(
          child: RecordingView(source: src, onStop: onStop ?? () {}),
        ),
      ),
    );
    return mq == null ? page : MediaQuery(data: mq, child: page);
  }

  testWidgets('fits a 360x640 phone at 1.3x text without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final src = _FakeSource();
    await tester.pumpWidget(app(
      src,
      mq: const MediaQueryData(
        size: Size(360, 640),
        textScaler: TextScaler.linear(1.3),
      ),
    ));
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Recording…'), findsOneWidget);
    expect(find.text('Stop & see report'), findsOneWidget);
    // A RenderFlex overflow is reported through FlutterError: none allowed.
    expect(tester.takeException(), isNull);
  });

  testWidgets('breath stops in the background and resumes in the foreground',
      (tester) async {
    final src = _FakeSource();
    await tester.pumpWidget(app(src));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('goes night-quiet after a minute untouched and wakes on touch',
      (tester) async {
    final src = _FakeSource();
    await tester.pumpWidget(app(src));
    await tester.pump(const Duration(milliseconds: 100));

    AnimatedOpacity fade() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(fade().opacity, 1.0);

    await tester.pump(RecordingView.dimAfter + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1)); // fade finishes
    expect(fade().opacity, lessThan(0.1));
    expect(tester.hasRunningAnimations, isFalse);

    // The waking touch must not reach the stop button underneath.
    bool stopped = false;
    // Same tree shape, new callback: the view's State (and its dimmed
    // flag) survives the re-pump.
    await tester.pumpWidget(app(src, onStop: () => stopped = true));
    await tester.tap(find.text('Stop & see report'), warnIfMissed: false);
    await tester.pump();
    expect(stopped, isFalse);
    expect(fade().opacity, 1.0);
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.hasRunningAnimations, isTrue);

    // Awake again, the button works.
    await tester.tap(find.text('Stop & see report'));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion holds the orb still and drops the ripples',
      (tester) async {
    final src = _FakeSource();
    await tester.pumpWidget(app(
      src,
      mq: const MediaQueryData(disableAnimations: true),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byIcon(Icons.nightlight_round), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
