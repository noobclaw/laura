import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstamp/main.dart';

void main() {
  testWidgets('app boots and shows its title bar', (tester) async {
    await tester.pumpWidget(const FieldStampApp());
    await tester.pump(); // one frame; the store loads asynchronously
    expect(find.byType(FieldStampApp), findsOneWidget);
    // The AppBar title renders regardless of async camera/sensor/store state.
    expect(find.text('FieldStamp'), findsWidgets);
    // Both bottom-nav destinations are present.
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });
}
