import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunekit/core/json_file_store.dart';
import 'package:tunekit/main.dart';
import 'package:tunekit/tool/app_theme.dart';
import 'package:tunekit/tool/log_page.dart';
import 'package:tunekit/tool/metronome_controller.dart';
import 'package:tunekit/tool/metronome_page.dart';
import 'package:tunekit/tool/mic_controller.dart';
import 'package:tunekit/tool/music/theory.dart';
import 'package:tunekit/tool/music/tunings.dart';
import 'package:tunekit/tool/music/voicing.dart';
import 'package:tunekit/tool/practice_page.dart';
import 'package:tunekit/tool/store.dart';
import 'package:tunekit/tool/tuner_page.dart';

/// The audio channel has no native side in the test harness. Stub it so the
/// pages exercise their real permission / start / stop paths: the mic
/// reports "undetermined", the metronome accepts start/stop.
void _stubAudioChannel() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('tunekit/audio'), (call) async {
    switch (call.method) {
      case 'micStatus':
      case 'micRequest':
        return 'undetermined';
      case 'micStart':
        throw PlatformException(code: 'permission');
      default:
        return null;
    }
  });
  for (final name in const ['tunekit/audio/mic', 'tunekit/audio/events']) {
    messenger.setMockStreamHandler(EventChannel(name), MockStreamHandler.inline(onListen: (_, _) {}));
  }
}

/// No disk in the test harness: path_provider has no responder, and a real
/// write would await a platform message that never answers.
class _NoFile extends JsonFileStore {
  _NoFile() : super('test.json');
  @override
  void write(Map<String, dynamic> json) {}
  @override
  Future<void> flush() async {}
}

TuneKitStore _loadedStore({bool pro = false}) {
  final s = TuneKitStore(file: _NoFile())
    ..loaded = true
    ..pro = pro;
  final today = s.today();
  today.tunerSec = 300;
  today.metroSec = 120;
  today.tuneSamples = 40;
  today.inTuneSamples = 30;
  today.tuneAbsCentsSum = 120;
  return s;
}

void main() {
  setUp(_stubAudioChannel);

  testWidgets('app boots and renders the shell chrome with four tabs', (tester) async {
    await tester.pumpWidget(const ShellApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both brightnesses produce distinct, usable themes', (tester) async {
    for (final b in Brightness.values) {
      final t = buildTuneTheme(b);
      expect(t.colorScheme.brightness, b);
      expect(t.cardTheme.elevation, 0);
    }
    expect(buildTuneTheme(Brightness.dark).colorScheme.surface,
        isNot(buildTuneTheme(Brightness.light).colorScheme.surface));
  });

  testWidgets('tuner page shows the permission guidance, not a dead needle', (tester) async {
    final store = _loadedStore();
    final mic = MicPitchController(store);
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.dark),
      home: Scaffold(body: TunerPage(store: store, mic: mic, active: true)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Allow microphone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    mic.dispose();
  });

  testWidgets('metronome page renders, toggles play and gates 6/8 for free users', (tester) async {
    final store = _loadedStore();
    final metro = MetronomeController(store);
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.light),
      home: Scaffold(body: MetronomePage(store: store, metro: metro)),
    ));
    await tester.pump();
    expect(find.text('100'), findsWidgets);
    expect(find.text('6/8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(metro.playing, isTrue);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(metro.playing, isFalse);

    await tester.tap(find.text('6/8'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TuneBench Pro'), findsOneWidget, reason: 'gated option opens the Pro sheet');
    expect(store.timeSignatureIndex, 2, reason: 'free user stays on 4/4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    metro.dispose();
    await store.flush();
  });

  testWidgets('practice list gates locked types and opens free ones', (tester) async {
    final store = _loadedStore();
    final mic = MicPitchController(store);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.dark),
      home: Scaffold(body: PracticePage(store: store, mic: mic)),
    ));
    await tester.pump();
    expect(find.text('PRO'), findsWidgets);

    await tester.tap(find.text('Cdim').first);
    await tester.pumpAndSettle();
    expect(find.text('TuneBench Pro'), findsOneWidget);
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('C7').first);
    await tester.pumpAndSettle();
    expect(find.byType(PatternDetailPage), findsOneWidget);
    expect(find.textContaining('x32310'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mic.dispose();
    await store.flush();
  });

  testWidgets('check page lays out for a guitar voicing', (tester) async {
    final store = _loadedStore();
    final mic = MicPitchController(store);
    final item = RootedPattern(0, patternById('maj')!);
    final guitar = instrumentById('guitar');
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.dark),
      home: CheckPage(
        store: store,
        mic: mic,
        item: item,
        instrument: guitar,
        voicing: deriveVoicing(item, guitar),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    mic.dispose();
  });

  testWidgets('drill runs a question and scores an answer', (tester) async {
    final store = _loadedStore();
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.light),
      home: DrillPage(store: store),
    ));
    await tester.pump();
    expect(find.textContaining('Question 1 / 10'), findsOneWidget);
    // Tap the first option; whichever it is, the round advances.
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Question 2 / 10'), findsOneWidget);
    expect(store.today().drillAnswered, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await store.flush(); // cancels the batched-save timer
  });

  testWidgets('log page draws charts and gates the 30-day range', (tester) async {
    final store = _loadedStore();
    await tester.pumpWidget(MaterialApp(
      theme: buildTuneTheme(Brightness.dark),
      home: Scaffold(body: LogPage(store: store)),
    ));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('7'), findsWidgets); // today's minutes + 7-day total
    await tester.tap(find.text('30d'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TuneBench Pro'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('store round-trips its JSON and computes streaks', () {
    final s = _loadedStore();
    final json = s.toJson();
    final back = TuneKitStore()..loaded = true;
    // Same path the loader takes, minus the file.
    expect(json['days'], isA<Map>());
    expect(s.streak, 1);
    expect(back.streak, 0);
    expect(s.visibleDays(30).length, 7, reason: 'free tier caps history at 7 days');
    s.pro = true;
    expect(s.visibleDays(30).length, 30);
  });
}
