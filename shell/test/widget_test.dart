import 'package:flutter_test/flutter_test.dart';
import 'package:tool_shell/main.dart';

void main() {
  testWidgets('shell boots and shows the tool home', (tester) async {
    await tester.pumpWidget(const ShellApp());
    expect(find.byType(ShellApp), findsOneWidget);
  });
}
