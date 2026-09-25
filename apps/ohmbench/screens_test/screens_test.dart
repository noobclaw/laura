// Local screenshot harness for the G4/G6b visual review (kb/UIUX规矩.md 5.1).
// Not part of `test/` (CI does not run it): `flutter test screens_test`
// renders real frames with real fonts into screens_test/out/*.png.
//
// The eight review shots are 1_…8_*.png; the editor_* shots cover every
// example idle and running.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/bench/words.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/schematic/document.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';
import 'package:ohmbench/tool/ui/home_screen.dart';
import 'package:ohmbench/tool/ui/lab_theme.dart';
import 'package:ohmbench/tool/ui/settings_screen.dart';

const _flutter = r'D:\dev\flutter\bin\cache\artifacts\material_fonts';

Future<void> loadShotFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final roboto = [
    '$_flutter\\roboto-regular.ttf',
    '$_flutter\\roboto-medium.ttf',
    '$_flutter\\roboto-bold.ttf',
  ];
  const deng = [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\Dengb.ttf'];
  await family('Roboto', roboto);
  await family('MaterialIcons', ['$_flutter\\materialicons-regular.otf']);
  await family(BenchType.mono, [
    'assets/fonts/MartianMono-Regular.ttf',
    'assets/fonts/MartianMono-Bold.ttf',
  ]);
  // Stand-ins for the iOS CJK face named in BenchType.fallback.
  await family('PingFang SC', deng);
  await family('Deng', deng);
  // Text that names no family falls back to the test default.
  await family('FlutterTest', roboto);
}

/// The production theme, with the CJK stand-in appended to every text style
/// so Chinese renders with real glyphs in the harness.
ThemeData shotTheme() {
  final t = buildOhmTheme();
  TextStyle? f(TextStyle? s) => s?.copyWith(
      fontFamilyFallback: [...?s.fontFamilyFallback, 'PingFang SC', 'Deng']);
  final x = t.textTheme;
  return t.copyWith(
    textTheme: x.copyWith(
      displayLarge: f(x.displayLarge),
      displayMedium: f(x.displayMedium),
      displaySmall: f(x.displaySmall),
      headlineLarge: f(x.headlineLarge),
      headlineMedium: f(x.headlineMedium),
      headlineSmall: f(x.headlineSmall),
      titleLarge: f(x.titleLarge),
      titleMedium: f(x.titleMedium),
      titleSmall: f(x.titleSmall),
      bodyLarge: f(x.bodyLarge),
      bodyMedium: f(x.bodyMedium),
      bodySmall: f(x.bodySmall),
      labelLarge: f(x.labelLarge),
      labelMedium: f(x.labelMedium),
      labelSmall: f(x.labelSmall),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  final element = tester.firstElement(find.byKey(const ValueKey('shot')));
  final boundary = element.renderObject! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
  final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png));
  Directory('screens_test/out').createSync(recursive: true);
  File('screens_test/out/$name.png')
      .writeAsBytesSync(bytes!.buffer.asUint8List());
}

Widget _frame(Widget home, {double textScale = 1, bool reduceMotion = false}) =>
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: shotTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
            // A notched phone: 47 pt status bar, 34 pt home indicator.
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _run(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('run-button')));
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)));
  await _settle(tester, 30);
}

ProjectStore _withData() {
  final store = ProjectStore();
  store.create(kExamples[0].title, kExamples[0].build());
  store.create(kExamples[3].title, kExamples[3].build());
  return store;
}

void main() {
  setUpAll(loadShotFonts);

  Future<void> sized(WidgetTester tester) async {
    // iPhone 14/15-class: 390 × 844 pt at 3×.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
  }

  testWidgets('1 home first open', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    await tester.pumpWidget(_frame(HomeScreen(store: ProjectStore())));
    await _settle(tester);
    await _shot(tester, '1_home_first_open_zh');
  });

  testWidgets('2 home with data', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    await tester.pumpWidget(_frame(HomeScreen(store: _withData())));
    await _settle(tester);
    await _shot(tester, '2_home_data_zh');
  });

  testWidgets('3 editor running', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    final store = ProjectStore();
    final project = store.create(kExamples[2].title, kExamples[2].build());
    await tester.pumpWidget(
        _frame(EditorScreen(store: store, project: project)));
    await tester.pump(const Duration(milliseconds: 100));
    await _run(tester);
    await _shot(tester, '3_editor_running_zh');
  });

  testWidgets('4 empty bench', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    final store = ProjectStore();
    final project = store.create('新电路', const SchematicDocument());
    await tester.pumpWidget(
        _frame(EditorScreen(store: store, project: project)));
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, '4_empty_bench_zh');
  });

  testWidgets('5 error state', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    final store = ProjectStore();
    // A DC source with a wire straight across it: a short the solver
    // refuses to put a number on.
    var doc = kExamples[0].build();
    final source = doc.parts.firstWhere((p) => p.kind == PartKind.dcSource);
    (doc, _) = doc.addWire(source.pins.first, source.pins.last);
    final project = store.create('短路', doc);
    await tester.pumpWidget(
        _frame(EditorScreen(store: store, project: project)));
    await tester.pump(const Duration(milliseconds: 100));
    await _run(tester);
    await _shot(tester, '5_error_short_zh');
  });

  testWidgets('6 dark: settings', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    await tester.pumpWidget(_frame(OhmSettingsScreen(store: _withData())));
    await _settle(tester, 10);
    await _shot(tester, '6_dark_settings_zh');
  });

  testWidgets('7 home at text scale 2.0', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'en';
    await tester.pumpWidget(
        _frame(HomeScreen(store: _withData()), textScale: 2));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await _shot(tester, '7_home_textscale2_en');
  });

  testWidgets('8 home in English', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'en';
    await tester.pumpWidget(_frame(HomeScreen(store: _withData())));
    await _settle(tester);
    await _shot(tester, '8_home_data_en');
  });

  testWidgets('9 home, reduce motion', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'en';
    await tester.pumpWidget(
        _frame(HomeScreen(store: ProjectStore()), reduceMotion: true));
    await _settle(tester, 4);
    await _shot(tester, '9_home_reduce_motion_en');
  });

  for (final ex in kExamples) {
    testWidgets('editor ${ex.id}', (tester) async {
      await sized(tester);
      BenchLanguage.override.value = 'en';
      final store = ProjectStore();
      var doc = ex.build();
      // Close the switches so the running shot shows current.
      for (final p in doc.parts) {
        if (p.closed == false) doc = doc.replacePart(p.copyWith(closed: true));
      }
      final project = store.create(ex.title, doc);
      await tester.pumpWidget(
          _frame(EditorScreen(store: store, project: project)));
      await tester.pump(const Duration(milliseconds: 100));
      await _shot(tester, 'editor_${ex.id}_idle');
      await _run(tester);
      await _shot(tester, 'editor_${ex.id}_run');
    });
  }
}
