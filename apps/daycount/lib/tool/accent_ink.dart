import 'dart:ui';

/// WCAG 2.x contrast ratio between [fg] (alpha-composited onto [bg]) and
/// [bg]. 1 is identical, 21 is black on white.
double contrastRatio(Color fg, Color bg) {
  final f = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = f > b ? f : b;
  final lo = f > b ? b : f;
  return (hi + 0.05) / (lo + 0.05);
}

/// WCAG AA for body text.
const double kContrastAA = 4.5;

/// WCAG AA for large text (≥ 18pt regular / 14pt bold): the card titles and
/// the day counts.
const double kContrastAALarge = 3.0;

const Color _white = Color(0xFFFFFFFF);
const Color _ink = Color(0xDD000000); // Colors.black87

/// Text colours for an event accent, chosen by measured contrast instead of
/// a luminance guess.
///
/// [fg] is white when white clears AA-large on the accent (so the big title
/// and digits keep the light-on-colour look), otherwise black87. Small text
/// must sit on [small]: the accent itself when [fg] already clears 4.5:1
/// there, else a dark band lerped toward black — the same tone the card
/// gradient fades into, so the band reads as part of the card.
class AccentInk {
  const AccentInk({
    required this.accent,
    required this.fg,
    required this.small,
  });

  /// The event colour itself.
  final Color accent;

  /// Text colour: white or black87.
  final Color fg;

  /// Background for small text (≤ ~16px): [accent] or a dark band.
  final Color small;

  /// True when small text needs the dark band rather than the accent.
  bool get banded => small != accent;

  /// Fill for pills / chips drawn on the accent: the dark band when one is
  /// needed, else a light wash that only raises the contrast of dark ink.
  Color get chip => banded ? small : const Color(0x3DFFFFFF);
}

/// Picks the text colour for [bg] by actually measuring WCAG contrast, and
/// decides whether small text needs a dark band. See [AccentInk].
AccentInk onColorFor(Color bg) {
  final fg = contrastRatio(_white, bg) >= kContrastAALarge ? _white : _ink;
  if (contrastRatio(fg, bg) >= kContrastAA) {
    return AccentInk(accent: bg, fg: fg, small: bg);
  }
  final band = Color.lerp(bg, const Color(0xFF000000), 0.32)!;
  // On the band whichever ink reads better wins (white for every accent the
  // editor offers; the check keeps custom colours honest).
  final bandFg =
      contrastRatio(_white, band) >= contrastRatio(_ink, band) ? _white : _ink;
  return AccentInk(accent: bg, fg: bandFg, small: band);
}
