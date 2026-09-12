import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:daycount/tool/accent_ink.dart';
import 'package:daycount/tool/models.dart';

void main() {
  test('contrastRatio matches the WCAG reference points', () {
    expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01));
    expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
        closeTo(1, 0.001));
    // The audit's numbers: white on the coral / blue / pink presets.
    expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFE7625F)),
        closeTo(3.33, 0.02));
    expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF3E9CE7)),
        closeTo(2.95, 0.02));
    expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFE06FAE)),
        closeTo(2.98, 0.02));
  });

  test('onColorFor clears WCAG AA on every preset event colour', () {
    for (final v in kEventColors) {
      final bg = Color(v);
      final ink = onColorFor(bg);
      final hex = v.toRadixString(16);
      // Small text sits on `small` (accent or dark band): body-text AA.
      expect(contrastRatio(ink.fg, ink.small), greaterThanOrEqualTo(kContrastAA),
          reason: 'small text on $hex');
      // Chips (pills, date row, day badge) drawn over the accent.
      expect(
        contrastRatio(ink.fg, Color.alphaBlend(ink.chip, bg)),
        greaterThanOrEqualTo(kContrastAA),
        reason: 'chip text on $hex',
      );
      // The big title / digits sit straight on the accent: large-text AA.
      expect(contrastRatio(ink.fg, bg), greaterThanOrEqualTo(kContrastAALarge),
          reason: 'large text on $hex');
    }
  });

  test('a light accent gets dark ink with no band', () {
    final ink = onColorFor(const Color(0xFFF2B705)); // amber
    expect(ink.fg, const Color(0xDD000000));
    expect(ink.banded, isFalse);
  });

  test('a mid-tone accent keeps white ink and bands its small text', () {
    final ink = onColorFor(const Color(0xFFE7625F)); // coral
    expect(ink.fg, const Color(0xFFFFFFFF));
    expect(ink.banded, isTrue);
    expect(ink.small, Color.lerp(const Color(0xFFE7625F), const Color(0xFF000000), 0.32));
  });
}
