// Shared by screens_test.dart and store_shots_test.dart: real fonts, the real
// theme, and a real-looking book. Not part of `test/` (CI does not run it).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:draftbook/core/l10n.dart';
import 'package:draftbook/tool/app_theme.dart';
import 'package:draftbook/tool/models.dart';
import 'package:draftbook/tool/store.dart';
import 'package:draftbook/tool/ui/line_gauge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _material = r'D:\dev\flutter\bin\cache\artifacts\material_fonts';

class TempDocs extends PathProviderPlatform {
  TempDocs(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  // The bundled faces, straight from assets/.
  await family('Newsreader', [
    'assets/fonts/Newsreader-Regular.ttf',
    'assets/fonts/Newsreader-SemiBold.ttf',
    'assets/fonts/Newsreader-Italic.ttf',
  ]);
  await family('NewsreaderDisplay', ['assets/fonts/NewsreaderDisplay-Medium.ttf']);
  // The system face stands in for SF (the iOS text-style families) and for
  // PingFang (the CJK fallback named in DbType.fallback).
  final roboto = [
    '$_material\\roboto-regular.ttf',
    '$_material\\roboto-medium.ttf',
    '$_material\\roboto-bold.ttf',
  ];
  for (final f in ['Roboto', 'CupertinoSystemText', 'CupertinoSystemDisplay', '.SF UI Text', '.SF UI Display']) {
    await family(f, roboto);
  }
  await family('MaterialIcons', ['$_material\\materialicons-regular.otf']);
  await family('PingFang SC', [r'C:\Windows\Fonts\Deng.ttf', r'C:\Windows\Fonts\Dengb.ttf']);
  await family('FlutterTest', roboto);
}

/// The app theme with the UI face falling back to the CJK stand-in, as iOS
/// does on its own.
ThemeData theme(Brightness b) {
  final t = buildDraftbookTheme(b, uiFontFamily: 'Roboto');
  return t.copyWith(textTheme: t.textTheme.apply(fontFamilyFallback: DbType.fallback));
}

void setUpHarness() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('draftbook_shots_');
    PathProviderPlatform.instance = TempDocs(tmp.path);
    await loadFonts();
  });
  setUp(LineGauge.resetMemory);
}

/// iOS controls and typography for the frame; must be undone inside the test.
void ios(bool on) {
  debugDefaultTargetPlatformOverride = on ? TargetPlatform.iOS : null;
}

Future<void> save(WidgetTester tester, String path) async {
  final boundary =
      tester.firstElement(find.byKey(const ValueKey('shot'))).renderObject! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> settle(WidgetTester tester, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void setLanguage(String code) => AppLanguage.override.value = code;

/// A store holding a real-looking novel in progress: three chapters, scenes in
/// every state, versions, a fortnight of writing and a streak.
DraftbookStore sampleStore({required bool zh, bool second = false}) {
  final s = DraftbookStore()..loaded = true;
  final p = s.addProject(
    title: zh ? '夜航船' : 'The Night Ferry',
    targetWords: zh ? 120000 : 80000,
  );
  final c1 = p.chapters.first..title = zh ? '港口的灯' : 'Harbour Lights';
  c1.scenes.first
    ..title = zh ? '末班船' : 'The last crossing'
    ..status = SceneStatus.done
    ..body = zh ? _zh1 : _en1;
  s.addScene(p, c1, title: zh ? '售票亭' : 'The ticket booth')
    ..status = SceneStatus.done
    ..body = zh ? _zh2 : _en2
    ..synopsis = zh ? '她第一次看见那张写错名字的船票。' : 'She sees the ticket with the wrong name on it.';
  final c2 = s.addChapter(p, title: zh ? '雾' : 'Fog');
  s.addScene(p, c2, title: zh ? '甲板' : 'On deck')
    ..status = SceneStatus.done
    ..body = zh ? _zh3 : _en3;
  final writing = s.addScene(p, c2, title: zh ? '无人回答的汽笛' : 'A horn nobody answers')
    ..status = SceneStatus.drafting
    ..body = zh ? _zh4 : _en4;
  s.addScene(p, c2, title: zh ? '靠岸之前' : 'Before landfall');
  final c3 = s.addChapter(p, title: zh ? '对岸' : 'The Far Shore');
  s.addScene(p, c3, title: zh ? '码头上的人' : 'The man on the pier').synopsis = zh ? '他手里拿着她的旧照片。' : 'He is holding an old photograph of her.';

  // Pad the finished chapters so the book has real weight on the fore-edge.
  c1.scenes.first.body = '${c1.scenes.first.body}\n\n${(zh ? _zhFill : _enFill) * 14}';
  c2.scenes.first.body = '${c2.scenes.first.body}\n\n${(zh ? _zhFill : _enFill) * 9}';

  p.lastSceneId = writing.id;
  writing.history
    ..add(SceneSnapshot(
        ms: DateTime.now().subtract(const Duration(days: 2, hours: 3)).millisecondsSinceEpoch,
        body: (zh ? _zh4 : _en4).split('\n\n').first))
    ..add(SceneSnapshot(
        ms: DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
        body: (zh ? _zh4 : _en4).split('\n\n').take(2).join('\n\n')));

  if (second) {
    final q = s.addProject(title: zh ? '短篇：十二月' : 'December (stories)');
    q.chapters.first.scenes.first.body = zh ? _zh2 : _en2;
    q.updatedMs = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    s.pro = true;
  }
  p.updatedMs = DateTime.now().millisecondsSinceEpoch;

  s.dailyLog.clear();
  final today = DateTime.now();
  const words = [620, 0, 410, 540, 780, 505, 0, 350, 610, 520, 700, 515, 560, 312];
  for (var i = 0; i < words.length; i++) {
    final d = DateTime(today.year, today.month, today.day - (words.length - 1 - i));
    s.dailyLog[dayKey(d)] = words[i];
  }
  return s;
}

const _en1 = 'The last ferry left at ten past eleven, and Mara was the only one who '
    'ran for it. The deckhand held the rope a second longer than he had to.\n\n'
    '"You nearly missed it," he said, as if it mattered to him.';
const _en2 = 'The booth smelled of diesel and oranges. The woman behind the glass '
    'slid the ticket across without looking up, and the name printed on it was '
    'not Mara\'s. It was her mother\'s.';
const _en3 = 'Fog came up off the water in sheets, and the lights of the harbour '
    'went out one at a time behind them, as if someone were walking along the '
    'quay switching them off.';
const _en4 = 'Somewhere past the breakwater the horn sounded, long and low, and '
    'nobody on the ferry moved.\n\n'
    'Mara counted to ten. Then she counted again, because the first time she '
    'had been listening for an answer instead of counting.\n\n'
    'The second horn came from the wrong side of the boat. She went to the rail '
    'and looked down into the fog, and the fog looked back, patient as a dog, '
    'and she understood that whoever was out there already knew her name';
const _enFill = 'The water moved under them like something breathing in its sleep, '
    'and nobody spoke of it. ';
const _zh1 = '末班船十一点十分开，只有林岚一个人是跑着赶上的。水手把缆绳多握了一秒。\n\n'
    '“差一点就错过了。”他说，好像这件事跟他有关系。';
const _zh2 = '售票亭里有柴油和橘子的味道。玻璃后面的女人头也不抬，把船票推了出来，'
    '上面印的不是林岚的名字，是她母亲的。';
const _zh3 = '雾一层一层从水面上升起来，港口的灯在他们身后一盏一盏熄灭，'
    '像有人沿着码头走过去，顺手把它们关掉。';
const _zh4 = '过了防波堤不远，汽笛响了，又长又低，船上没有一个人动。\n\n'
    '林岚数到十，又重新数了一遍，因为第一遍她其实是在等回音，而不是在数数。\n\n'
    '第二声汽笛从船的另一边传来。她走到栏杆边往下看，雾也在看她，耐心得像一条狗。'
    '她忽然明白，外面那个人早就知道她叫什么';
const _zhFill = '水在船底下起伏，像某种睡着了还在呼吸的东西，没有人提起它。';
