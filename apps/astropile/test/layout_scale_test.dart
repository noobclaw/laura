import 'dart:io';

import 'package:astropile/core/l10n.dart';
import 'package:astropile/tool/app_theme.dart';
import 'package:astropile/tool/astropile_tool.dart';
import 'package:astropile/tool/engine/asterism.dart';
import 'package:astropile/tool/engine/stack.dart';
import 'package:astropile/tool/models.dart';
import 'package:astropile/tool/store.dart';
import 'package:astropile/tool/ui/result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The worst case the audit named: a 360 px phone, the OS text size at 130%
/// and English copy, which runs longer than the Chinese it was laid out for.
/// Every panel that used to have a fixed height or a rigid Row must render
/// without a single RenderFlex overflow.
const _narrow = Size(360, 640);

Future<void> pumpNarrowEnglish(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = _narrow;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppLanguage.override.value = 'en';
  addTearDown(() => AppLanguage.override.value = null);
  await tester.pumpWidget(MediaQuery(
    data: const MediaQueryData(
      size: _narrow,
      textScaler: TextScaler.linear(1.3),
    ),
    child: MaterialApp(
      locale: const Locale('en'),
      theme: buildAstroTheme(Brightness.light),
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

FrameReport _report(String id, {bool ref = false, AlignFailure? failure}) => FrameReport(
      frameId: id,
      name: '$id.jpg',
      isReference: ref,
      starsDetected: 120,
      matchedStars: 96,
      rmsPixels: 0.42,
      score: 82,
      failure: failure,
    );

void main() {
  testWidgets('home hero survives 360 px + 130% text + English', (tester) async {
    final tool = AstropileTool();
    tool.store
      ..loaded = true
      ..stackedCount = 12; // the count column widens the hero's bottom row
    await pumpNarrowEnglish(
      tester,
      Scaffold(body: Builder(builder: (context) => tool.buildHome(context))),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('night sky'), findsOneWidget);
    expect(find.text('stacks made'), findsOneWidget);
  });

  testWidgets('result summary strip survives 360 px + 130% text + English',
      (tester) async {
    // dispose() deletes the raw file's parent, so hand it a scratch dir of
    // its own rather than anything shared.
    final dir = Directory.systemTemp.createTempSync('astropile_layout_');
    final raw = File('${dir.path}/stack.raw')..writeAsBytesSync(const []);
    final outcome = StackOutcome(
      rawPath: raw.path,
      width: 4000,
      height: 3000,
      reports: [
        _report('a', ref: true),
        _report('b'),
        _report('c', failure: AlignFailure.values.first),
      ],
      usedFrames: 2,
      mode: StackMode.median,
    );
    await pumpNarrowEnglish(
      tester,
      ResultScreen(store: AstroStore()..loaded = true, outcome: outcome),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('frames stacked'), findsOneWidget);
    expect(find.text('excluded'), findsOneWidget);

    // Pop the screen so its dispose runs before the temp dir check.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
}
