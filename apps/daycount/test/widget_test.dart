import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/main.dart';

void main() {
  testWidgets('app boots and shows its title bar', (tester) async {
    await tester.pumpWidget(const DaycountApp());
    await tester.pump(); // one frame; the store loads asynchronously
    expect(find.byType(DaycountApp), findsOneWidget);
    // The AppBar title renders regardless of async store state.
    expect(find.widgetWithText(AppBar, '倒数日'), findsOneWidget);
  });
}
