import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/tool/flip_digit.dart';
import 'package:daycount/tool/hero_card.dart';
import 'package:daycount/tool/models.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
      ),
    );

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
}
