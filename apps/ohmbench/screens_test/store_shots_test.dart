// Store screenshots (G8b "first image is the ad"): the real app rendered in
// a captioned frame. Run: flutter test screens_test/store_shots_test.dart
// Output: screens_test/out/store/{appstore,play}/{en,zh}/N.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohmbench/bench/words.dart';
import 'package:ohmbench/tool/examples.dart';
import 'package:ohmbench/tool/store.dart';
import 'package:ohmbench/tool/ui/brand.dart';
import 'package:ohmbench/tool/ui/editor_screen.dart';
import 'package:ohmbench/tool/ui/home_screen.dart';
import 'package:ohmbench/tool/ui/lab_theme.dart';

const _fonts = r'D:\dev\flutter\bin\cache\artifacts\material_fonts';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await family('Roboto', ['$_fonts\\roboto-regular.ttf', '$_fonts\\roboto-medium.ttf', '$_fonts\\roboto-bold.ttf']);
  await family('MaterialIcons', ['$_fonts\\materialicons-regular.otf']);
  await family('Deng', [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\Dengb.ttf']);
}

ThemeData _theme() {
  final t = buildOhmTheme();
  return t.copyWith(
      textTheme: t.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: ['Deng']));
}

class _Shot {
  const _Shot(this.titleEn, this.subEn, this.titleZh, this.subZh, this.build,
      {this.run = false});

  final String titleEn, subEn, titleZh, subZh;
  final Widget Function(ProjectStore store) build;
  final bool run;
}

Widget _editor(ProjectStore store, int example, {bool closeSwitch = true}) {
  var doc = kExamples[example].build();
  if (closeSwitch) {
    for (final p in doc.parts) {
      if (!p.closed) doc = doc.replacePart(p.copyWith(closed: true));
    }
  }
  final project = store.create(kExamples[example].title, doc);
  return EditorScreen(store: store, project: project);
}

final _shots = <_Shot>[
  _Shot('Draw it. Run it.', 'Charge flows. The scope traces it.', '画出来,跑起来',
      '电荷流动,示波器同步描绘', (s) => _editor(s, 2), run: true),
  _Shot('Numbers you can trust', 'SPICE-grade solver, on your phone', '数,算得对',
      'SPICE 同口径求解器,就在手机上', (s) => _editor(s, 0), run: true),
  _Shot('Watch a tank ring', 'Close a switch; see ~500 Hz decay', '看 LC 振荡',
      '合上开关,约 500 Hz 衰减振荡', (s) => _editor(s, 3), run: true),
  _Shot('Flip a switch mid-run', 'The capacitor charges from where it was',
      '运行中拨开关', '电容从上一刻的电压继续充', (s) => _editor(s, 1), run: true),
  _Shot('Nothing you build is lost', 'Every step saves itself · works offline',
      '作品丢不了', '每一步自动保存 · 全离线', (s) {
    s.pro = true; // three saved circuits is a Pro library
    s.create(kExamples[0].title, kExamples[0].build());
    s.create(kExamples[3].title, kExamples[3].build());
    s.create(kExamples[2].title, kExamples[2].build());
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(children: [OhmMark(size: 22), SizedBox(width: 10), OhmWordmark()]),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.tune_rounded))],
      ),
      body: SafeArea(child: HomeScreen(store: s)),
    );
  }),
];

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.sub, required this.child});

  final String title, sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: _body(),
    );
  }

  Widget _body() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF15293A), Bench.background],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 70),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontFamilyFallback: ['Deng'],
                  color: Bench.ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 10),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontFamilyFallback: ['Deng'],
                  color: Bench.charge,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 34),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(38)),
                  border: Border.all(color: const Color(0xFF3A5363), width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: Bench.positive.withValues(alpha: 0.18),
                        blurRadius: 40),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: 390, height: 844, child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _save(WidgetTester tester, String path) async {
  final boundary = tester.firstElement(find.byKey(const ValueKey('shot'))).renderObject!
      as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(_loadFonts);

  for (final (store, w) in [('appstore', 1284.0), ('play', 1389.0)]) {
    for (final lang in ['en', 'zh']) {
      for (var i = 0; i < _shots.length; i++) {
        testWidgets('$store $lang ${i + 1}', (tester) async {
          tester.view.physicalSize = Size(w, 2778);
          tester.view.devicePixelRatio = 3;
          BenchLanguage.override.value = lang;
          final shot = _shots[i];
          final ps = ProjectStore();
          await tester.pumpWidget(RepaintBoundary(
            key: const ValueKey('shot'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme(),
              home: _Frame(
                title: lang == 'zh' ? shot.titleZh : shot.titleEn,
                sub: lang == 'zh' ? shot.subZh : shot.subEn,
                child: shot.build(ps),
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 200));
          if (shot.run) {
            await tester.tap(find.byIcon(Icons.play_arrow_rounded));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
            for (var k = 0; k < 34; k++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          } else {
            for (var k = 0; k < 30; k++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
          }
          await _save(tester, 'screens_test/out/store/$store/$lang/${i + 1}.png');
        });
      }
    }
  }
}
