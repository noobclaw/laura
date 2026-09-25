import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/bench/words.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';
import 'package:ohmbench/tool/ui/home_screen.dart';
import 'package:ohmbench/tool/ui/lab_theme.dart';
import 'package:ohmbench/tool/ui/settings_screen.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
      theme: buildOhmTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

Widget _home(ProjectStore store, {double scale = 1}) =>
    _app(HomeScreen(store: store), scale: scale);

void main() {
  group('contrast (F11, V8) — the one (dark) theme', () {
    const pairs = <String, (Color, Color, double)>{
      'ink on board': (Bench.ink, Bench.background, 4.5),
      'ink on panel': (Bench.ink, Bench.panel, 4.5),
      'dim ink on board': (Bench.inkDim, Bench.background, 4.5),
      'dim ink on panel': (Bench.inkDim, Bench.panel, 4.5),
      'dim ink on top bar': (Bench.inkDim, Bench.backgroundTop, 4.5),
      'label on charge button': (Bench.onCharge, Bench.charge, 4.5),
      'glyph on stop button': (Bench.onError, Bench.error, 4.5),
      'error text on error fill':
          (Bench.onErrorContainer, Bench.errorContainer, 4.5),
      'warning on board': (Bench.warning, Bench.background, 4.5),
      'error on panel': (Bench.error, Bench.panel, 4.5),
      'readout cyan on board': (Bench.positive, Bench.background, 4.5),
      'charge on board': (Bench.charge, Bench.background, 4.5),
      'hairline control edge': (Bench.outline, Bench.background, 1.5),
    };
    for (final e in pairs.entries) {
      test(e.key, () {
        final (fg, bg, min) = e.value;
        expect(_contrast(fg, bg), greaterThanOrEqualTo(min),
            reason: '${e.key}: ${_contrast(fg, bg).toStringAsFixed(2)}:1');
      });
    }
  });

  test('raw aesthetic values live only in the theme file (2.2)', () {
    final raw = RegExp(
        r'Color\(0x|circular\(\d|Curves\.|Duration\(milliseconds: \d+\)|fontFamily: .Roboto');
    // Non-visual timers (save coalescing, rerun debounce) are behaviour.
    final allowed = {'lab_theme.dart'};
    final offenders = <String>[];
    for (final f in Directory('lib/tool/ui').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (allowed.contains(name)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!raw.hasMatch(line)) continue;
        if (line.contains('Timer(')) continue;
        offenders.add('$name:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('HapticFeedback is only called through BenchHaptics (F14)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('haptics.dart')) continue;
      if (f.readAsStringSync().contains('HapticFeedback.')) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });

  test('the display face is bundled, never fetched (V4)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: MartianMono'));
    expect(pubspec, isNot(contains('google_fonts')));
    expect(File('assets/fonts/MartianMono-Regular.ttf').existsSync(), isTrue);
    expect(File('assets/fonts/MartianMono-OFL.txt').existsSync(), isTrue);
  });

  group('home screen accessibility', () {
    setUp(() => BenchLanguage.override.value = 'en');
    tearDown(() => BenchLanguage.override.value = null);

    testWidgets('lays out at text scale 2.0 without overflow (F10, V7)',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = ProjectStore()
        ..create(kExamples[0].title, kExamples[0].build());
      await tester.pumpWidget(_home(store, scale: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap targets are ≥ 44 pt and labelled (F7, F11)',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final store = ProjectStore()
        ..create(kExamples[0].title, kExamples[0].build());
      await tester.pumpWidget(_home(store));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('editor and settings accessibility', () {
    setUp(() => BenchLanguage.override.value = 'en');
    tearDown(() => BenchLanguage.override.value = null);

    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('editor: targets, labels, contrast (F7, F11)', (tester) async {
      await phone(tester);
      final handle = tester.ensureSemantics();
      final store = ProjectStore();
      final project = store.create('RC', kExamples[1].build());
      await tester.pumpWidget(_app(EditorScreen(store: store, project: project)));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('editor lays out at text scale 2.0 (F10)', (tester) async {
      await phone(tester);
      final store = ProjectStore();
      final project = store.create('RC', kExamples[1].build());
      await tester.pumpWidget(
          _app(EditorScreen(store: store, project: project), scale: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings: targets, labels, contrast (F7, F11)',
        (tester) async {
      await phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(OhmSettingsScreen(store: ProjectStore())));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
