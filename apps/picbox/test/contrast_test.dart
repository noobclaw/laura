import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/tool/app_theme.dart';
import 'package:picbox/tool/models.dart';
import 'package:picbox/tool/ui/widgets.dart';

/// WCAG 2.x contrast ratio, computed here independently of the app helper so
/// the helper itself is under test too.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Composite [top] (with alpha) over an opaque [under].
Color _over(Color top, Color under) => Color.alphaBlend(top, under);

void main() {
  final light = buildPicboxTheme(Brightness.light);
  final cs = light.colorScheme;
  final accents = [for (final k in ToolKind.values) ToolMeta.of(k).color];

  test('tool "process" buttons: foreground reaches AA on every accent', () {
    for (final c in accents) {
      final fill = toolFillColor(c);
      final fg = onToolColor(fill);
      expect(_contrast(fg, fill), greaterThanOrEqualTo(4.5), reason: 'accent $c → fill $fill / fg $fg');
    }
  });

  test('result summary card: text reaches AA across the deep gradient', () {
    for (final c in accents) {
      final top = toolDeepColor(c);
      final bottom = Color.lerp(top, Colors.black, 0.2)!;
      final fg = onToolColor(top);
      expect(_contrast(fg, top), greaterThanOrEqualTo(4.5), reason: 'top of $c');
      expect(_contrast(fg, bottom), greaterThanOrEqualTo(4.5), reason: 'bottom of $c');
      // The dimmed "before" size (85 % fg) and the saved-percent pill
      // (fg on a 22 % black scrim) must hold up on the lighter end too.
      expect(_contrast(_over(fg.withValues(alpha: 0.85), top), top), greaterThanOrEqualTo(4.5));
      final pill = _over(Colors.black.withValues(alpha: 0.22), top);
      expect(_contrast(fg, pill), greaterThanOrEqualTo(4.5), reason: 'pill on $c');
    }
  });

  test('result row "−N%" uses scheme primary on the light card', () {
    final card = light.cardTheme.color ?? cs.surface;
    expect(_contrast(cs.primary, card), greaterThanOrEqualTo(4.5), reason: 'primary $card');
    // Sanity: the raw lime it replaced really was below AA here.
    expect(_contrast(ToolColors.compress, card), lessThan(4.5));
  });

  test('PRO badge uses the scheme primary / onPrimary pair', () {
    expect(_contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
    expect(_contrast(Colors.white, ToolColors.compress), lessThan(4.5));
  });

  test('contrastRatio helper agrees with the independent formula', () {
    expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
    for (final c in accents) {
      expect(contrastRatio(Colors.white, c), closeTo(_contrast(Colors.white, c), 1e-9));
    }
  });
}
