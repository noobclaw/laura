// Store screenshots: the real app, rendered with the real fonts inside an
// editorial caption frame. Run: flutter test screens_test/store_shots_test.dart
// Output: store/screenshots/{appstore,play}/{en,zh}/N.png
// (App Store 1284×2778, Play 1389×2778.)
import 'package:draftbook/tool/app_theme.dart';
import 'package:draftbook/tool/store.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:draftbook/tool/ui/history_screen.dart';
import 'package:draftbook/tool/ui/home_screen.dart';
import 'package:draftbook/tool/ui/line_gauge.dart';
import 'package:draftbook/tool/ui/outline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

class _Shot {
  const _Shot(this.titleEn, this.subEn, this.titleZh, this.subZh, this.build, {this.then});
  final String titleEn, subEn, titleZh, subZh;
  final Widget Function(DraftbookStore s) build;
  final Future<void> Function(WidgetTester t)? then;
}

final _shots = <_Shot>[
  _Shot('Pick up mid-sentence', 'Open it and your last lines are there. One tap, and so is the caret.',
      '从停笔那一句接着写', '打开就是你的稿子，点一下，光标回到原处', (s) => HomeScreen(store: s)),
  _Shot('A quiet page to write on', 'Saved at every pause. The toolbar never leaves your thumb.',
      '只有稿子的书写页', '每次停顿都自动保存，工具条一直在拇指下', (s) {
    final p = s.projects.first;
    return EditorScreen(store: s, projectId: p.id, sceneId: s.lastScene(p)!.scene.id);
  }),
  _Shot('The whole book on one screen', 'Chapters and scenes, dragged into the order the story wants.',
      '整本书一屏看完', '章与场景，拖一下就换成故事要的顺序', (s) => OutlineScreen(store: s, projectId: s.projects.first.id)),
  _Shot('Every draft is kept', 'Twenty versions of every scene. Restore any of them, and undo that too.',
      '写过的每一稿都在', '每个场景留 20 版，随时换回，也能撤销', (s) {
    final p = s.projects.first;
    return HistoryScreen(store: s, projectId: p.id, sceneId: s.lastScene(p)!.scene.id);
  }),
  _Shot('Today, set in ink', 'Your daily goal on a typesetter\'s line gauge. No account, no cloud.',
      '今日字数，一眼看见', '每日目标画在排字行规上；无账号，不联网', (s) => HomeScreen(store: s),
      then: (t) => t.tap(find.byType(LineGauge))),
];

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.sub, required this.child});
  final String title, sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return Material(
      color: c.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 64),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Text(title,
                textAlign: TextAlign.center,
                style: DbType.title.copyWith(color: c.ink, fontSize: 36, height: 1.1)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(sub,
                textAlign: TextAlign.center,
                style: DbType.byline.copyWith(color: c.inkMuted, fontSize: 18, height: 1.35)),
          ),
          const SizedBox(height: 18),
          // The gauge's caret, as a mark between caption and screen.
          Center(child: SizedBox(width: 40, height: 2, child: ColoredBox(color: c.accent))),
          const SizedBox(height: 26),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              // The whole screen, thumb bar included: the frame shrinks the
              // phone rather than crop what the app puts under the thumb.
              child: Center(
                child: AspectRatio(
                  aspectRatio: 390 / 844,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.ruleStrong, width: 1.5),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(width: 390, height: 844, child: child),
                      ),
                    ),
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

void main() {
  setUpHarness();

  for (final (store, w) in [('appstore', 1284.0), ('play', 1389.0)]) {
    for (final lang in ['en', 'zh']) {
      for (var i = 0; i < _shots.length; i++) {
        testWidgets('$store $lang ${i + 1}', (tester) async {
          tester.view.physicalSize = Size(w, 2778);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          ios(true);
          setLanguage(lang);
          final shot = _shots[i];
          final s = sampleStore(zh: lang == 'zh');
          final inner = MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              devicePixelRatio: 3,
              padding: EdgeInsets.only(top: 47, bottom: 34),
              viewPadding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => shot.build(s)),
            ),
          );
          await tester.pumpWidget(RepaintBoundary(
            key: const ValueKey('shot'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme(Brightness.light),
              home: _Frame(
                title: lang == 'zh' ? shot.titleZh : shot.titleEn,
                sub: lang == 'zh' ? shot.subZh : shot.subEn,
                child: inner,
              ),
            ),
          ));
          await settle(tester);
          if (shot.then != null) {
            await shot.then!(tester);
            await settle(tester);
          }
          await save(tester, 'store/screenshots/$store/$lang/${i + 1}.png');
          await tester.pump(const Duration(seconds: 1));
          ios(false);
        });
      }
    }
  }
}
