// Local screenshot harness for the G6b visual review. Not part of `test/`
// (CI does not run it): `flutter test screens_test` renders real frames with
// real fonts into screens_test/out/*.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/bench/words.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';
import 'package:ohmbench/tool/ui/home_screen.dart';
import 'package:ohmbench/tool/ui/lab_theme.dart';

const _flutter = r'D:\dev\flutter\bin\cache\artifacts\material_fonts';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    '$_flutter\\roboto-regular.ttf',
    '$_flutter\\roboto-medium.ttf',
    '$_flutter\\roboto-bold.ttf',
  ]);
  await family('MaterialIcons', ['$_flutter\\materialicons-regular.otf']);
  await family('Deng', [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\Dengb.ttf']);
  // Text painted straight onto canvases (part labels) names no family and
  // falls back to the test default; give that default real glyphs too.
  await family('FlutterTest', ['$_flutter\\roboto-regular.ttf']);
}

ThemeData _theme(Brightness b) {
  final t = buildOhmTheme(b);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deng']),
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

Widget _frame(Widget home, Brightness b) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: home,
      ),
    );

class _Home extends StatelessWidget {
  const _Home(this.store);
  final ProjectStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('OhmBench'),
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined)),
          ],
        ),
        body: SafeArea(child: HomeScreen(store: store)),
      );
}

void main() {
  setUpAll(_loadFonts);

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
  }

  for (final lang in ['en', 'zh']) {
    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('home $lang ${b.name}', (tester) async {
        await sized(tester);
        BenchLanguage.override.value = lang;
        final store = ProjectStore();
        if (b == Brightness.dark) {
          store.create(kExamples[0].title, kExamples[0].build());
          store.create(kExamples[3].title, kExamples[3].build());
        }
        await tester.pumpWidget(_frame(_Home(store), b));
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _shot(tester, 'home_${lang}_${b.name}');
      });
    }
  }

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
          _frame(EditorScreen(store: store, project: project), Brightness.dark));
      await tester.pump(const Duration(milliseconds: 100));
      await _shot(tester, 'editor_${ex.id}_idle');
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1500)));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _shot(tester, 'editor_${ex.id}_run');
    });
  }

  testWidgets('editor empty', (tester) async {
    await sized(tester);
    BenchLanguage.override.value = 'zh';
    final store = ProjectStore();
    final project = store.create('新电路', kExamples[0].build().removeIds({}).copyWith(parts: [], wires: []));
    await tester.pumpWidget(
        _frame(EditorScreen(store: store, project: project), Brightness.dark));
    await tester.pump(const Duration(milliseconds: 100));
    await _shot(tester, 'editor_empty_zh');
    await tester.tap(find.text('电阻').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    // ignore: avoid_print
    print('DELETE ICONS: ${find.byIcon(Icons.delete_outline_rounded).evaluate().length}');
    await _shot(tester, 'editor_added_zh');
  });
}
