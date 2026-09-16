import 'package:flutter/material.dart';

/// A [TextEditingController] that renders the editor's light Markdown inline
/// while you type: `#` headings, `>` quotes, `**bold**`, `*italic*`.
///
/// Two deliberate decisions, both from PLAN.md §8 风险 1 ("the formatting bugs
/// in the incumbent are the price of a heavyweight rich-text engine"):
///
/// 1. **The marks stay visible.** Hiding `**` would change the mapping between
///    the text and what is drawn, which is exactly where caret and selection
///    bugs come from. They are dimmed instead, so the line still reads as
///    prose while every offset stays honest.
/// 2. **While an IME is composing, only that line steps aside.** A Chinese or
///    Japanese writer's composing region needs its own underline and must not
///    be re-spanned mid-word. Handing the *whole document* back to the
///    framework for that would drop every heading and quote style on every
///    keystroke of every pinyin syllable — the text would visibly reflow and
///    snap back for the app's primary audience. So the composing line is drawn
///    plainly, with the composing range underlined, and every other line keeps
///    its formatting.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  static final RegExp _heading = RegExp(r'^(\s{0,3}#{1,6}\s+)(.*)$');
  static final RegExp _quote = RegExp(r'^(\s{0,3}>\s?)(.*)$');
  static final RegExp _inline =
      RegExp(r'(\*\*)(.+?)(\*\*)|(?<!\*)(\*)(?!\s)([^*]+?)(\*)(?!\*)');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final cs = Theme.of(context).colorScheme;
    final mark = base.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.45));

    final composing =
        withComposing && value.isComposingRangeValid && !value.composing.isCollapsed
            ? value.composing
            : null;

    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineEnd = offset + line.length;
      final touchesComposing = composing != null &&
          composing.start <= lineEnd &&
          composing.end >= offset;
      if (touchesComposing) {
        _appendComposingLine(spans, line, offset, composing, base);
      } else {
        _appendLine(spans, line, base, mark, cs);
      }
      if (i != lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
      offset = lineEnd + 1; // + the newline
    }
    return TextSpan(style: base, children: spans);
  }

  /// The line an IME is composing on: no Markdown styling (the text is still
  /// being formed), with the composing range underlined the way the framework
  /// would have done it.
  void _appendComposingLine(
    List<InlineSpan> out,
    String line,
    int lineStart,
    TextRange composing,
    TextStyle base,
  ) {
    final start = (composing.start - lineStart).clamp(0, line.length);
    final end = (composing.end - lineStart).clamp(0, line.length);
    if (start > 0) out.add(TextSpan(text: line.substring(0, start), style: base));
    if (end > start) {
      out.add(TextSpan(
        text: line.substring(start, end),
        style: base.copyWith(decoration: TextDecoration.underline),
      ));
    }
    if (end < line.length) {
      out.add(TextSpan(text: line.substring(end), style: base));
    }
  }

  void _appendLine(
    List<InlineSpan> out,
    String line,
    TextStyle base,
    TextStyle mark,
    ColorScheme cs,
  ) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final hashes = heading.group(1)!;
      final level = '#'.allMatches(hashes).length;
      out.add(TextSpan(text: hashes, style: mark));
      _appendInline(
        out,
        heading.group(2)!,
        base.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: (base.fontSize ?? 17) * (level == 1 ? 1.28 : 1.12),
          height: 1.35,
        ),
        mark,
      );
      return;
    }

    final quote = _quote.firstMatch(line);
    if (quote != null) {
      out.add(TextSpan(text: quote.group(1)!, style: mark));
      _appendInline(
        out,
        quote.group(2)!,
        base.copyWith(
          fontStyle: FontStyle.italic,
          color: cs.onSurfaceVariant,
        ),
        mark,
      );
      return;
    }

    _appendInline(out, line, base, mark);
  }

  void _appendInline(
    List<InlineSpan> out,
    String text,
    TextStyle base,
    TextStyle mark,
  ) {
    var index = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > index) {
        out.add(TextSpan(text: text.substring(index, m.start), style: base));
      }
      final bold = m.group(1) != null;
      final open = bold ? m.group(1)! : m.group(4)!;
      final body = bold ? m.group(2)! : m.group(5)!;
      final close = bold ? m.group(3)! : m.group(6)!;
      out
        ..add(TextSpan(text: open, style: mark))
        ..add(TextSpan(
          text: body,
          style: bold
              ? base.copyWith(fontWeight: FontWeight.w700)
              : base.copyWith(fontStyle: FontStyle.italic),
        ))
        ..add(TextSpan(text: close, style: mark));
      index = m.end;
    }
    if (index < text.length) {
      out.add(TextSpan(text: text.substring(index), style: base));
    }
  }
}

/// What the toolbar above the keyboard does to the text. Kept out of the
/// widget so it can be unit-tested without a keyboard: every button is
/// "wrap the selection" or "prefix the line", and both have to behave when
/// the selection is empty, inverted, or has never been placed at all.
abstract final class MarkdownEdits {
  /// Wraps the selection in [mark] (or inserts an empty pair and puts the
  /// caret in the middle when nothing is selected). Toggles off when the
  /// selection is already wrapped.
  static TextEditingValue wrap(TextEditingValue value, String mark) {
    final text = value.text;
    final sel = _safeSelection(value);
    final start = sel.start;
    final end = sel.end;

    // Already wrapped → unwrap, so the same button is an on/off switch.
    // For the single `*`, the neighbours must not themselves be asterisks:
    // italicising a selection inside `**bold**` would otherwise peel one star
    // off each side and silently turn bold into italic.
    final singleInsideDouble = mark == '*' &&
        ((start >= 2 && text.substring(start - 2, start - 1) == '*') ||
            (end + 2 <= text.length && text.substring(end + 1, end + 2) == '*'));
    if (!singleInsideDouble &&
        start >= mark.length &&
        end + mark.length <= text.length &&
        text.substring(start - mark.length, start) == mark &&
        text.substring(end, end + mark.length) == mark) {
      final next = text.substring(0, start - mark.length) +
          text.substring(start, end) +
          text.substring(end + mark.length);
      return TextEditingValue(
        text: next,
        selection: TextSelection(
          baseOffset: start - mark.length,
          extentOffset: end - mark.length,
        ),
      );
    }

    final selected = text.substring(start, end);
    final next =
        '${text.substring(0, start)}$mark$selected$mark${text.substring(end)}';
    return TextEditingValue(
      text: next,
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: start + mark.length)
          : TextSelection(
              baseOffset: start + mark.length,
              extentOffset: end + mark.length,
            ),
    );
  }

  /// Adds [prefix] to the start of the line the caret is on, or removes it if
  /// it is already there.
  static TextEditingValue linePrefix(TextEditingValue value, String prefix) {
    final text = value.text;
    final sel = _safeSelection(value);
    // `lastIndexOf('\n', 0)` finds a newline *at* 0, which would put the caret
    // on line 2 when the text starts with a blank line; with the caret at 0
    // there is nothing before it to search.
    final lineStart =
        sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
    final rest = text.substring(lineStart);
    if (rest.startsWith(prefix)) {
      final next = text.substring(0, lineStart) + rest.substring(prefix.length);
      final shift = prefix.length;
      return TextEditingValue(
        text: next,
        selection: TextSelection(
          baseOffset: (sel.start - shift).clamp(lineStart, next.length),
          extentOffset: (sel.end - shift).clamp(lineStart, next.length),
        ),
      );
    }
    final next = text.substring(0, lineStart) + prefix + rest;
    return TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: sel.start + prefix.length,
        extentOffset: sel.end + prefix.length,
      ),
    );
  }

  /// Inserts [snippet] at the caret, replacing any selection.
  static TextEditingValue insert(TextEditingValue value, String snippet) {
    final text = value.text;
    final sel = _safeSelection(value);
    final next =
        text.substring(0, sel.start) + snippet + text.substring(sel.end);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + snippet.length),
    );
  }

  /// A selection that is always inside the text and never inverted. A field
  /// that has not been focused yet reports offset -1, and acting on that is
  /// how a formatting button ends up throwing instead of formatting.
  static TextSelection _safeSelection(TextEditingValue value) {
    final len = value.text.length;
    if (!value.selection.isValid) {
      return TextSelection.collapsed(offset: len);
    }
    final start = value.selection.start.clamp(0, len);
    final end = value.selection.end.clamp(0, len);
    return TextSelection(
      baseOffset: start <= end ? start : end,
      extentOffset: start <= end ? end : start,
    );
  }
}
