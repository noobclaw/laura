// Local screenshot harness for the G4/G6b visual review (kb/UIUX规矩.md 5.1):
// `flutter test screens_test/screens_test.dart` renders the real screens with
// the real fonts into screens_test/out/*.png.
import 'package:draftbook/tool/models.dart';
import 'package:draftbook/tool/store.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:draftbook/tool/ui/history_screen.dart';
import 'package:draftbook/tool/ui/home_screen.dart';
import 'package:draftbook/tool/ui/line_gauge.dart';
import 'package:draftbook/tool/ui/outline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _frame(Widget home, {Brightness b = Brightness.light, double scale = 1, bool reduce = false}) =>
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduce,
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: child!,
        ),
        home: home,
      ),
    );

void main() {
  setUpHarness();

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(DraftbookStore s) build, {
    String lang = 'zh',
    Brightness b = Brightness.light,
    double scale = 1,
    bool empty = false,
    Future<void> Function(WidgetTester t, DraftbookStore s)? then,
  }) async {
    await phone(tester);
    ios(true);
    setLanguage(lang);
    final s = empty ? (DraftbookStore()..loaded = true) : sampleStore(zh: lang == 'zh');
    await tester.pumpWidget(_frame(build(s), b: b, scale: scale));
    await settle(tester);
    if (then != null) {
      await then(tester, s);
      await settle(tester);
    }
    await save(tester, 'screens_test/out/$name.png');
    await tester.pump(const Duration(seconds: 1));
    ios(false);
  }

  Project book(DraftbookStore s) => s.projects.first;
  SceneRef writing(DraftbookStore s) => s.lastScene(book(s))!;

  // -- The eight required states (kb 5.1 G4) --------------------------------

  testWidgets('01 home, first open', (t) => shoot(t, '01_home_first_open_zh', (s) => HomeScreen(store: s), empty: true));
  testWidgets('02 home, with a book', (t) => shoot(t, '02_home_data_zh', (s) => HomeScreen(store: s)));
  testWidgets('03 editor', (t) => shoot(t, '03_editor_zh',
      (s) => EditorScreen(store: s, projectId: book(s).id, sceneId: writing(s).scene.id)));
  testWidgets('04 empty state: no versions yet', (t) => shoot(t, '04_empty_history_zh', (s) {
        final first = s.firstScene(book(s))!;
        return HistoryScreen(store: s, projectId: book(s).id, sceneId: first.scene.id);
      }));
  testWidgets('05 error: a save failed', (t) => shoot(t, '05_error_zh', (s) {
        s.storageTrouble.value = const StorageTrouble(
          kind: 'save',
          detail: 'No space left on device (errno = 28)',
        );
        return HomeScreen(store: s);
      }));
  testWidgets('06 dark', (t) => shoot(t, '06_dark_zh', (s) => HomeScreen(store: s), b: Brightness.dark));
  testWidgets('07 text at 200%', (t) => shoot(t, '07_textscale2_zh', (s) => HomeScreen(store: s), scale: 2));
  testWidgets('08 English', (t) => shoot(t, '08_home_en', (s) => HomeScreen(store: s), lang: 'en'));

  // -- The rest of the app, for the review ----------------------------------

  testWidgets('outline', (t) => shoot(t, '09_outline_zh', (s) => OutlineScreen(store: s, projectId: book(s).id)));
  testWidgets('outline en dark', (t) => shoot(t, '10_outline_en_dark',
      (s) => OutlineScreen(store: s, projectId: book(s).id), lang: 'en', b: Brightness.dark));
  testWidgets('stats sheet', (t) => shoot(t, '11_stats_zh', (s) => HomeScreen(store: s),
      then: (t, s) async => t.tap(find.byType(LineGauge))));
  testWidgets('shelf sheet', (t) => shoot(t, '12_shelf_en', (s) => HomeScreen(store: s),
      lang: 'en', then: (t, s) async => t.tap(find.byTooltip('Your books'))));
  testWidgets('export sheet', (t) => shoot(t, '13_export_en', (s) => OutlineScreen(store: s, projectId: book(s).id),
      lang: 'en', then: (t, s) async => t.tap(find.byTooltip('Export'))));
  testWidgets('history with versions', (t) => shoot(t, '14_history_en',
      (s) => HistoryScreen(store: s, projectId: book(s).id, sceneId: writing(s).scene.id), lang: 'en'));
  testWidgets('editor dark en', (t) => shoot(t, '15_editor_en_dark',
      (s) => EditorScreen(store: s, projectId: book(s).id, sceneId: writing(s).scene.id),
      lang: 'en', b: Brightness.dark));
  testWidgets('first open en dark', (t) => shoot(t, '16_first_open_en_dark', (s) => HomeScreen(store: s),
      lang: 'en', b: Brightness.dark, empty: true));
  testWidgets('outline at 200%', (t) => shoot(t, '17_outline_textscale2_en',
      (s) => OutlineScreen(store: s, projectId: book(s).id), lang: 'en', scale: 2));
  testWidgets('editor at 200%', (t) => shoot(t, '18_editor_textscale2_zh',
      (s) => EditorScreen(store: s, projectId: book(s).id, sceneId: writing(s).scene.id), scale: 2));
}
