import 'package:draftbook/tool/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countWords', () {
    test('counts Latin runs between separators', () {
      expect(countWords('the quick brown fox'), 4);
      expect(countWords('  leading and trailing  '), 3);
      expect(countWords('line one\nline two'), 4);
    });

    test('counts every CJK character as one word', () {
      expect(countWords('今天天气很好'), 6);
      // Mixed: four Chinese characters plus one Latin word.
      expect(countWords('他说 hello 世界'), 5);
    });

    test('punctuation on its own is not a word', () {
      expect(countWords('— * * * —'), 0);
      expect(countWords('...'), 0);
      expect(countWords("don't stop"), 2);
      expect(countWords('你好,世界。'), 4);
    });

    test('empty text has no words', () {
      expect(countWords(''), 0);
      expect(countWords('   \n\n  '), 0);
    });
  });

  test('countChars ignores whitespace', () {
    expect(countChars('ab cd\nef'), 6);
    expect(countChars('今天 天气'), 4);
  });

  test('groupedCount inserts thousands separators', () {
    expect(groupedCount(0), '0');
    expect(groupedCount(999), '999');
    expect(groupedCount(1000), '1,000');
    expect(groupedCount(1234567), '1,234,567');
    expect(groupedCount(-4200), '-4,200');
  });

  test('dayKey is the local calendar day, zero padded', () {
    expect(dayKey(DateTime(2026, 9, 6, 23, 59)), '2026-09-06');
    expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('a scene without a title falls back to its position', () {
    final s = Scene(id: 'a');
    expect(s.displayTitle(0), isNotEmpty);
    s.title = '  雨夜  ';
    expect(s.displayTitle(0), '雨夜');
  });

  test('project progress is null until a target is set', () {
    final p = Project(id: 'p');
    expect(p.progress, isNull);
    p.targetWords = 100;
    expect(p.progress, 0);
  });
}
