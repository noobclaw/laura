import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/tool/flip_digit.dart';
import 'package:daycount/tool/hero_card.dart';
import 'package:daycount/tool/models.dart';

Widget _host(Widget child,
        {bool reduceMotion = false, double textScale = 1.0}) =>
    MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
      ),
    );

CountdownEvent _inDays(int days, {String id = 'a', String title = 'Trip'}) {
  final today = DateTime.now();
  return CountdownEvent(
    id: id,
    title: title,
    date: DateTime(today.year, today.month, today.day)
        .add(Duration(days: days)),
  );
}

void main() {
  testWidgets('FlipNumber ratchets from 0 to its value', (tester) async {
    await tester.pumpWidget(
        _host(const FlipNumber(value: 42, textColor: Colors.white)));
    // Two digit tiles, both resting on 0 before the first flip.
    expect(find.byType(FlipDigit), findsNWidgets(2));
    expect(find.text('4'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('4'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('FlipNumber snaps straight to its value under reduced motion',
      (tester) async {
    await tester.pumpWidget(_host(
      const FlipNumber(value: 7, textColor: Colors.white),
      reduceMotion: true,
    ));
    await tester.pump();
    expect(find.text('7'), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('FlipDigit flips to a new value when its digit changes',
      (tester) async {
    Widget build(int d) => _host(FlipDigit(
          digit: d,
          style: const TextStyle(fontSize: 40),
          width: 30,
          height: 46,
          ratchetFromZero: false,
        ));
    await tester.pumpWidget(build(3));
    await tester.pump();
    expect(find.text('3'), findsWidgets);
    await tester.pumpWidget(build(2));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('FeaturedCard shows the flip digits for a future day',
      (tester) async {
    final today = DateTime.now();
    final event = CountdownEvent(
      id: 'a',
      title: 'Trip',
      date: DateTime(today.year, today.month, today.day).add(const Duration(days: 12)),
    );
    await tester.pumpWidget(_host(FeaturedCard(
      event: event,
      status: statusOf(event, today),
      progress: null,
      onTap: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsOneWidget);
    expect(find.byType(FlipDigit), findsNWidgets(2));
    expect(find.byType(ConfettiOverlay), findsNothing);
  });

  testWidgets('FeaturedCard celebrates today with confetti', (tester) async {
    final today = DateTime.now();
    final event = CountdownEvent(id: 'b', title: 'Now', date: today);
    await tester.pumpWidget(_host(FeaturedCard(
      event: event,
      status: statusOf(event, today),
      progress: null,
      onTap: () {},
    )));
    // The confetti loops forever, so pump a fixed span instead of settling.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ConfettiOverlay), findsOneWidget);
    expect(find.byType(FlipDigit), findsNothing);
    expect(find.text('🎉'), findsOneWidget);
  });

  testWidgets('FlipNumber reads to assistive tech as one number',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        _host(const FlipNumber(value: 42, textColor: Colors.white)));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.byType(FlipNumber));
    expect(node.label, '42');
    // No per-digit children leak through.
    expect(find.bySemanticsLabel('4'), findsNothing);
    handle.dispose();
  });

  testWidgets('FlipNumber keeps its tiles when the digit count grows',
      (tester) async {
    await tester.pumpWidget(_host(const FlipNumber(
        value: 99, textColor: Colors.white, ratchetFromZero: false)));
    await tester.pumpAndSettle();
    final unitsBefore = tester.state(find.byKey(const ValueKey('flip-place-0')));
    await tester.pumpWidget(_host(const FlipNumber(
        value: 100, textColor: Colors.white, ratchetFromZero: false)));
    await tester.pumpAndSettle();
    expect(find.byType(FlipDigit), findsNWidgets(3));
    // The units tile is the same State object, i.e. it flipped in place.
    expect(tester.state(find.byKey(const ValueKey('flip-place-0'))),
        same(unitsBefore));
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('FlipNumber does not ratchet new digits after first display',
      (tester) async {
    await tester.pumpWidget(
        _host(const FlipNumber(value: 9, textColor: Colors.white)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
        _host(const FlipNumber(value: 10, textColor: Colors.white)));
    await tester.pump();
    // The new tens tile starts on 1 instead of counting in from 0.
    final tens = tester.widget<FlipDigit>(
        find.byKey(const ValueKey('flip-place-1')));
    expect(tens.ratchetFromZero, isFalse);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('FeaturedCard survives a large system text scale',
      (tester) async {
    final event = _inDays(12);
    final today = DateTime.now();
    await tester.pumpWidget(
      _host(
        FeaturedCard(
          event: event,
          status: statusOf(event, today),
          progress: 0.5,
          onTap: () {},
        ),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FlipDigit), findsNWidgets(2));
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    // Digits are drawn unscaled inside tiles sized for the scale.
    for (final t in tester.widgetList<Text>(
        find.descendant(of: find.byType(FlipDigit), matching: find.byType(Text)))) {
      expect(t.textScaler, TextScaler.noScaling);
    }
  });

  testWidgets('FeaturedCard on the day survives a large text scale',
      (tester) async {
    final today = DateTime.now();
    final event = CountdownEvent(id: 'b', title: 'Now', date: today);
    await tester.pumpWidget(
      _host(
        FeaturedCard(
          event: event,
          status: statusOf(event, today),
          progress: null,
          onTap: () {},
        ),
        textScale: 1.3,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('🎉'), findsOneWidget);
  });

  testWidgets('FeaturedCard reads as one sentence', (tester) async {
    final handle = tester.ensureSemantics();
    final event = _inDays(42);
    final today = DateTime.now();
    await tester.pumpWidget(_host(FeaturedCard(
      event: event,
      status: statusOf(event, today),
      progress: null,
      onTap: () {},
    )));
    await tester.pumpAndSettle();
    // The card is a merge boundary: the sentence lives in the merged data.
    final data = tester.getSemantics(find.byType(FeaturedCard)).getSemanticsData();
    expect(data.label, contains('Trip'));
    expect(data.label, contains('in 42 days'));
    expect(data.label, isNot(contains('4,')));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel('42'), findsNothing);
    handle.dispose();
  });

  testWidgets('PressScale shrinks while held and releases on tap',
      (tester) async {
    await tester.pumpWidget(_host(PressScale(
      child: InkWell(onTap: () {}, child: const SizedBox(width: 100, height: 40)),
    )));
    final g = await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1));
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
