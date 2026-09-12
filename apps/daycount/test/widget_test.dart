import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/main.dart';
import 'package:daycount/tool/hero_card.dart';

void main() {
  testWidgets('app boots and shows its title bar', (tester) async {
    await tester.pumpWidget(const DaycountApp());
    await tester.pump(); // one frame; the store loads asynchronously
    expect(find.byType(DaycountApp), findsOneWidget);
    // The AppBar title renders regardless of async store state.
    // Under `flutter test` the app boots in the 'en' locale.
    expect(find.widgetWithText(AppBar, 'Daybird'), findsOneWidget);
  });

  testWidgets('empty store shows the Daybird mark and the add FAB',
      (tester) async {
    // `flutter test` registers the host's Dart-side path_provider (windows /
    // linux), so load() gets a real documents directory and then awaits real
    // file I/O — which FakeAsync never delivers, leaving the home on its
    // progress spinner forever. Mark the (still empty) store loaded up front
    // so the empty state is what gets built.
    tool.store.loaded = true;
    await tester.pumpWidget(const DaycountApp());
    await tester.pump();
    // Let the empty state's fade-in finish.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BirdMark), findsOneWidget);
    expect(find.text('No days yet'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(PressScale), findsWidgets);
  });
}
