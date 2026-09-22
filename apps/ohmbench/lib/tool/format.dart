import 'dart:math' as math;

import 'schematic/document.dart';

/// SI-prefixed numbers, the way an electronics person writes them.
///
/// Formatting is three significant figures with an engineering prefix
/// ("4.70 kΩ" is written "4.7 kΩ"; trailing zeros go). Parsing accepts what
/// people actually type on a phone keyboard: `4.7k`, `4k7`, `10u`, `10µ`,
/// `2.2M`, `2.2meg`, `100m`, `1e-6`, with or without a unit after it.

const _prefixes = <int, String>{
  -15: 'f',
  -12: 'p',
  -9: 'n',
  -6: 'µ',
  -3: 'm',
  0: '',
  3: 'k',
  6: 'M',
  9: 'G',
  12: 'T',
};

/// `formatSi(4700, 'Ω')` → `4.7 kΩ`. Zero prints as `0 Ω`.
String formatSi(double value, String unit, {int digits = 3}) {
  if (value.isNaN) return '— $unit'.trim();
  if (value.isInfinite) return '${value < 0 ? '−' : ''}∞ $unit'.trim();
  if (value == 0) return '0 $unit'.trim();
  final negative = value < 0;
  final magnitude = value.abs();
  var exponent = (math.log(magnitude) / math.ln10).floor();
  var engineering = (exponent / 3).floor() * 3;
  engineering = engineering.clamp(-15, 12);
  var scaled = magnitude / math.pow(10, engineering);
  // Rounding can carry 999.6 up to 1000 — move to the next prefix instead of
  // printing "1000 mV".
  var text = _significant(scaled, digits);
  if (double.parse(text) >= 1000 && engineering < 12) {
    engineering += 3;
    scaled = magnitude / math.pow(10, engineering);
    text = _significant(scaled, digits);
  }
  exponent = engineering;
  final prefix = _prefixes[exponent] ?? '';
  return '${negative ? '−' : ''}$text $prefix$unit'.trim();
}

String _significant(double scaled, int digits) {
  final intDigits = scaled >= 100
      ? 3
      : scaled >= 10
          ? 2
          : 1;
  final decimals = math.max(0, digits - intDigits);
  var text = scaled.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

const _multipliers = <String, double>{
  'f': 1e-15,
  'p': 1e-12,
  'n': 1e-9,
  'u': 1e-6,
  'µ': 1e-6,
  'μ': 1e-6,
  'm': 1e-3,
  'k': 1e3,
  'K': 1e3,
  'M': 1e6,
  'G': 1e9,
  'T': 1e12,
};

/// Parses a typed value, or returns null when it is not a number. The unit
/// symbol (Ω, ohm, F, H, V, A, Hz) may follow and is ignored.
double? parseSi(String input) {
  var text = input.trim().replaceAll(',', '.').replaceAll(' ', '');
  if (text.isEmpty) return null;
  text = text.replaceFirst(
      RegExp(r'(ohms?|Ω|Hz|hz|F|H|V|A)$', caseSensitive: true), '');
  if (text.isEmpty) return null;

  // "2.2meg" / "2.2MEG": SPICE's spelling of mega, since "m" is milli.
  final meg = RegExp(r'^([+-]?\d*\.?\d+)(meg|MEG|Meg)$').firstMatch(text);
  if (meg != null) return _finite(double.tryParse(meg.group(1)!), 1e6);

  // "4k7" — the prefix standing in for the decimal point.
  final infix = RegExp(r'^([+-]?\d+)([fpnuµμmkKMGT])(\d+)$').firstMatch(text);
  if (infix != null) {
    final whole = double.tryParse('${infix.group(1)}.${infix.group(3)}');
    return _finite(whole, _multipliers[infix.group(2)]!);
  }

  final suffix =
      RegExp(r'^([+-]?\d*\.?\d+(?:[eE][+-]?\d+)?)([fpnuµμmkKMGT]?)$')
          .firstMatch(text);
  if (suffix == null) return null;
  final base = double.tryParse(suffix.group(1)!);
  final prefix = suffix.group(2)!;
  return _finite(base, prefix.isEmpty ? 1 : _multipliers[prefix]!);
}

double? _finite(double? base, double multiplier) {
  if (base == null) return null;
  final v = base * multiplier;
  return v.isFinite ? v : null;
}

/// The unit a part's main value is measured in.
String unitOf(PartKind kind) => switch (kind) {
      PartKind.resistor => 'Ω',
      PartKind.capacitor => 'F',
      PartKind.inductor => 'H',
      PartKind.dcSource || PartKind.sineSource => 'V',
      PartKind.currentSource => 'A',
      _ => '',
    };

/// The label drawn beside a part: its value, and a sine's frequency.
String partValueLabel(SchematicPart part) => switch (part.kind) {
      PartKind.diode || PartKind.ground || PartKind.toggleSwitch => '',
      PartKind.sineSource =>
        '${formatSi(part.value, 'V')} · ${formatSi(part.secondaryValue, 'Hz')}',
      _ => formatSi(part.value, unitOf(part.kind)),
    };
