import 'dart:io';
import 'dart:math' as math;

import 'package:draftbook/main.dart';
import 'package:draftbook/core/l10n.dart';
import 'package:draftbook/tool/app_theme.dart';
import 'package:draftbook/tool/haptics.dart';
import 'package:draftbook/tool/store.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:draftbook/tool/ui/line_gauge.dart';
import 'package:draftbook/tool/ui/outline_screen.dart';
import 'package:draftbook/tool/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The design system's promises as tests (kb/UIUX规矩.md F7, F10, F11, 2.2).

class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('draftbook_design_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tmp.path);
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Throwaway directory.
    }
  });

  setUp(() {
    tool.store.projects.clear();
    tool.store.dailyLog.clear();
    tool.store.pro = false;
    tool.store.loaded = true;
    LineGauge.resetMemory();
  });

  for (final (name, c) in [('light', DbColors.light), ('dark', DbColors.dark)]) {
    test('$name: text pairs clear WCAG AA', () {
      final body = <String, (Color, Color)>{
        'ink on paper': (c.ink, c.paper),
        'ink on page': (c.ink, c.page),
        'muted on paper': (c.inkMuted, c.paper),
        'muted on page': (c.inkMuted, c.page),
        'accent on paper': (c.accent, c.paper),
        'accent on page': (c.accent, c.page),
        'on-accent on accent': (c.onAccent, c.accent),
        'signal on page': (c.signal, c.page),
        'on-signal-wash on signal-wash': (c.onSignalWash, c.signalWash),
      };
      for (final e in body.entries) {
        expect(_contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5), reason: e.key);
      }
      // Control borders and gauge ticks: non-text, 3:1.
      expect(_contrast(c.ruleStrong, c.paper), greaterThanOrEqualTo(3), reason: 'ruleStrong on paper');
      expect(_contrast(c.ruleStrong, c.page), greaterThanOrEqualTo(3), reason: 'ruleStrong on page');
    });
  }

  Future<void> pumpHome(WidgetTester tester, {double scale = 1, bool withBook = true}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (withBook) {
      final p = tool.store.addProject(title: 'The Long Night Bus to Nowhere', targetWords: 80000);
      tool.store.addChapter(p, title: 'Departure');
      tool.store.updateSceneBody(
        p,
        tool.store.firstScene(p)!.scene,
        'The bus slowed under the bridge and she counted the lights until the '
        'driver said her name, which nobody on that route should have known.',
      );
    }
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(scale),
      ),
      child: const DraftbookApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  for (final withBook in [true, false]) {
    final label = withBook ? 'a book' : 'the blank page';
    testWidgets('$label lays out at 2× text without overflow (F10)', (tester) async {
      await pumpHome(tester, scale: 2, withBook: withBook);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: tap targets ≥44pt and labelled (F7, F11)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester, withBook: withBook);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  // The two screens a writer spends the day in get the same checks as home.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget Function(DraftbookStore s) build, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = tool.store;
    final p = s.addProject(title: 'The Long Night Bus to Nowhere', targetWords: 80000);
    final ch = s.addChapter(p, title: 'Departure, and everything after it');
    s.addScene(p, ch, title: 'The driver who knew her name');
    s.updateSceneBody(p, s.firstScene(p)!.scene, 'The bus slowed under the bridge. ' * 12);
    await tester.pumpWidget(MaterialApp(
      theme: buildDraftbookTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: build(s),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  final screens = <String, Widget Function(DraftbookStore)>{
    'editor': (s) {
      final p = s.projects.first;
      return EditorScreen(store: s, projectId: p.id, sceneId: s.firstScene(p)!.scene.id);
    },
    'outline': (s) => OutlineScreen(store: s, projectId: s.projects.first.id),
  };
  for (final e in screens.entries) {
    testWidgets('${e.key} lays out at 2× text without overflow (F10)', (tester) async {
      await pumpScreen(tester, e.value, scale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${e.key}: tap targets, labels and contrast (F7, F11)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, e.value);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('the editor bar keeps ≥8pt between neighbouring keys (F7)', (tester) async {
    await pumpScreen(tester, screens['editor']!);
    final keys = [
      for (final tip in ['Bold', 'Italic', 'Heading', 'Quote', 'Scene break', 'Previous scene', 'Next scene'])
        tester.getRect(find.byTooltip(tip)),
    ]..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < keys.length; i++) {
      expect(keys[i].left - keys[i - 1].right, greaterThanOrEqualTo(8), reason: 'gap before key $i');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('storage errors are said in the language of the page (F6, F16)', () {
    AppLanguage.override.value = 'zh';
    expect(plainStorageReason('FileSystemException: OS Error: No space left on device, errno = 28'),
        '手机存储空间不足');
    expect(plainStorageReason('OS Error: Permission denied, errno = 13'), '没有写入这个文件的权限');
    AppLanguage.override.value = 'en';
    expect(plainStorageReason('errno = 28'), 'this phone is out of storage');
    expect(plainStorageReason('something odd'), contains('something odd'));
    AppLanguage.override.value = null;
  });

  test('the goal milestone buzzes once per day, not once per launch (F14)', () {
    Haptics.resetMilestone();
    expect(Haptics.milestoneOnce('2026-09-25'), isTrue);
    expect(Haptics.milestoneOnce('2026-09-25'), isFalse);
    expect(Haptics.milestoneOnce('2026-09-26'), isTrue);
  });

  testWidgets('reduced motion: the gauge is at its end state on the first frame (F12)',
      (tester) async {
    tool.store.dailyLog[_today()] = 320;
    tool.store.addProject(title: 'Night Bus');
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: DraftbookApp(),
    ));
    await tester.pump();
    expect(find.text('320'), findsOneWidget);
    // Let the store's write-coalescing timer run out.
    await tester.pump(const Duration(seconds: 1));
  });

  test('raw colours, radii, curves and haptics live only in the token files (kb 2.2)', () {
    final offenders = <String>[];
    final raw = RegExp(
      r'Color\(0x|(?<![A-Za-z])Colors\.(?!transparent)|BorderRadius\.circular\(|Curves\.|HapticFeedback\.|Duration\((milliseconds|seconds):'
      // Spacing and press scale come from DbSpace / DbMotion too.
      r'|SizedBox\((height|width): [0-9]|(?<![A-Za-z])scale: [0-9.]|minHeight: [0-9]',
    );
    // Behaviour timers (autosave debounce, write coalescing) are not motion.
    const timers = {'store.dart', 'editor_screen.dart'};
    for (final f in Directory('lib/tool').listSync(recursive: true).whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.dart') || name == 'app_theme.dart' || name == 'haptics.dart') continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final m = raw.firstMatch(lines[i]);
        if (m == null) continue;
        if (m.group(0)!.startsWith('Duration(') && timers.contains(name)) continue;
        offenders.add('$name:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty);
  });
}

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
