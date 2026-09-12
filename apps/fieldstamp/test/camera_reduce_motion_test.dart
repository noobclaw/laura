import 'dart:io';

import 'package:fieldstamp/tool/camera_screen.dart';
import 'package:fieldstamp/tool/models.dart';
import 'package:fieldstamp/tool/sensors.dart';
import 'package:fieldstamp/tool/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reduced motion collapses every duration to zero. A zero-length "flight"
/// used to complete synchronously inside the first build and call
/// `setState` while the parent was still building (2026-09-11 audit P1-1).
void main() {
  Widget reducedMotion(Widget child) => MaterialApp(
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
            child: Scaffold(body: child),
          ),
        ),
      );

  testWidgets('capture under reduced motion lands without an exception',
      (tester) async {
    final store = FieldStampStore();
    final sensors = SensorHub();
    await tester.pumpWidget(
        reducedMotion(CameraScreen(store: store, sensors: sensors)));
    await tester.pump();

    final photo = StampPhoto(
      id: 'p1',
      fileName: 'p1.jpg',
      projectId: store.currentProjectId,
      capturedAt: DateTime.now(),
    );
    // The state class is private; the callback is `@visibleForTesting`.
    (tester.state(find.byType(CameraScreen)) as dynamic).onCaptured(photo);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Nothing flies: the photo went straight to the gallery entry.
    expect(find.byType(FlyingThumb), findsNothing);
    expect(find.bySemanticsLabel('Open gallery'), findsOneWidget);
  });

  testWidgets('a zero-duration FlyingThumb lands after the frame, not in it',
      (tester) async {
    var landed = 0;
    var showing = true;
    await tester.pumpWidget(reducedMotion(StatefulBuilder(
      builder: (ctx, setState) => Stack(
        children: [
          if (showing)
            FlyingThumb(
              file: File('/nonexistent.jpg'),
              from: Offset.zero,
              to: const Offset(100, 100),
              size: 48,
              duration: Duration.zero,
              onLanded: () => setState(() {
                landed++;
                showing = false;
              }),
            ),
        ],
      ),
    )));
    // Landing is deferred to after the first frame — never during build.
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(landed, 1);
    expect(find.byType(FlyingThumb), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
