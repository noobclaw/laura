import 'package:flutter_test/flutter_test.dart';
import 'package:echo_jot/main.dart';
import 'package:echo_jot/tool/note.dart';

void main() {
  testWidgets('app boots without crashing', (tester) async {
    await tester.pumpWidget(const ShellApp());
    await tester.pump();
    expect(find.byType(ShellApp), findsOneWidget);
  });

  group('firstSentenceTitle', () {
    test('takes the first sentence', () {
      expect(firstSentenceTitle('买牛奶。然后去银行。'), '买牛奶');
      expect(firstSentenceTitle('Buy milk. Then bank.'), 'Buy milk');
    });

    test('truncates long text', () {
      final title = firstSentenceTitle('这是一段非常非常长的没有任何标点的开头文字用来测试截断行为是否正确');
      expect(title.length, 25); // 24 chars + ellipsis
      expect(title.endsWith('…'), isTrue);
    });

    test('handles empty input', () {
      expect(firstSentenceTitle('  '), '(未转写)');
    });
  });
}
