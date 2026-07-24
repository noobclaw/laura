import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_alarm/main.dart';
import 'package:clean_alarm/tool/store.dart';

void main() {
  testWidgets('app boots and shows its title bar', (tester) async {
    // A bare store (no scheduler) keeps the widget test free of plugin calls.
    final store = AlarmStore();
    store.loaded = true;
    await tester.pumpWidget(CleanAlarmApp(store: store));
    await tester.pump();
    expect(find.byType(CleanAlarmApp), findsOneWidget);
    expect(find.widgetWithText(AppBar, '干净闹钟'), findsOneWidget);
    // Empty state guidance renders when there are no alarms.
    expect(find.text('还没有闹钟'), findsOneWidget);
  });
}
