import 'package:draftbook/tool/ui/markdown_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue v(String text, {int? base, int? extent}) => TextEditingValue(
      text: text,
      selection: base == null
          ? const TextSelection.collapsed(offset: -1)
          : TextSelection(baseOffset: base, extentOffset: extent ?? base),
    );

void main() {
  group('wrap', () {
    test('wraps a selection and keeps it selected', () {
      final out = MarkdownEdits.wrap(v('a brave word', base: 2, extent: 7), '**');
      expect(out.text, 'a **brave** word');
      expect(out.selection.textInside(out.text), 'brave');
    });

    test('a second tap unwraps', () {
      final once = MarkdownEdits.wrap(v('a brave word', base: 2, extent: 7), '**');
      final twice = MarkdownEdits.wrap(once, '**');
      expect(twice.text, 'a brave word');
      expect(twice.selection.textInside(twice.text), 'brave');
    });

    test('an empty selection leaves the caret between the marks', () {
      final out = MarkdownEdits.wrap(v('ab', base: 1), '*');
      expect(out.text, 'a**b');
      expect(out.selection.baseOffset, 2);
    });

    test('an inverted selection is handled the same way', () {
      final out = MarkdownEdits.wrap(v('a brave word', base: 7, extent: 2), '*');
      expect(out.text, 'a *brave* word');
    });

    test('a field that was never focused formats at the end instead of '
        'throwing', () {
      final out = MarkdownEdits.wrap(v('unfocused'), '**');
      expect(out.text, 'unfocused****');
      expect(out.selection.baseOffset, 11);
    });
  });

  test('italic does not peel a star off a bold run', () {
    // Selection sits inside **bold**; the old unwrap branch turned it italic.
    final out = MarkdownEdits.wrap(v('a **brave** word', base: 4, extent: 9), '*');
    expect(out.text, 'a ***brave*** word');
  });

  group('linePrefix', () {
    test('adds and removes a heading mark on the caret line', () {
      final added = MarkdownEdits.linePrefix(v('one\ntwo', base: 5), '# ');
      expect(added.text, 'one\n# two');
      final removed = MarkdownEdits.linePrefix(added, '# ');
      expect(removed.text, 'one\ntwo');
    });

    test('works on the first line', () {
      final out = MarkdownEdits.linePrefix(v('hello', base: 0), '> ');
      expect(out.text, '> hello');
      expect(out.selection.baseOffset, 2);
    });

    test('a caret at offset 0 of text that starts with a blank line stays on '
        'line 1', () {
      final out = MarkdownEdits.linePrefix(v('\nsecond', base: 0), '# ');
      expect(out.text, '# \nsecond');
    });
  });

  test('insert replaces the selection', () {
    final out = MarkdownEdits.insert(v('ab', base: 0, extent: 2), '\n* * *\n');
    expect(out.text, '\n* * *\n');
    expect(out.selection.baseOffset, out.text.length);
  });

  testWidgets('the controller renders marks without changing the text',
      (tester) async {
    final c = MarkdownEditingController(text: '# Title\n**bold** and *slanted*');
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          span = c.buildTextSpan(context: context, withComposing: false);
          return const SizedBox.shrink();
        }),
      ),
    );
    // Whatever the styling, the characters must come back out unchanged —
    // that is what keeps the caret and the selection honest.
    expect(span.toPlainText(), c.text);
    final styles = <TextStyle?>[];
    span.visitChildren((s) {
      if (s is TextSpan) styles.add(s.style);
      return true;
    });
    expect(styles.any((s) => s?.fontWeight == FontWeight.w700), isTrue);
    expect(styles.any((s) => s?.fontStyle == FontStyle.italic), isTrue);
    c.dispose();
  });
}
