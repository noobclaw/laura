import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tool_shell/main.dart';

void main() {
  testWidgets('shell boots and shows the tool home', (tester) async {
    await tester.pumpWidget(const ShellApp());
    expect(find.byType(ShellApp), findsOneWidget);
    // The tool owns the first screen: the shell adds no AppBar.
    expect(find.byType(AppBar), findsNothing);
  });
}
