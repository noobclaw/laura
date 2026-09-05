/// Instrument presets for the tuner and the per-string chord check.
library;

import 'theory.dart';

class Instrument {
  const Instrument({
    required this.id,
    required this.nameEn,
    required this.nameZh,
    required this.strings,
    this.free = false,
  });

  final String id;
  final String nameEn;
  final String nameZh;

  /// Open-string MIDI notes from the lowest-pitched (thickest) string up.
  /// Empty for chromatic mode.
  final List<int> strings;
  final bool free;

  bool get isChromatic => strings.isEmpty;

  /// Frets a chord voicing may use; guitars have plenty, a violin has none.
  bool get hasFrets => id == 'guitar' || id == 'ukulele' || id == 'bass';

  /// The string whose open pitch is nearest to [midi] (fractional MIDI is
  /// fine). Returns the index into [strings]. In chromatic mode returns -1.
  int nearestString(double midi) {
    if (strings.isEmpty) return -1;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < strings.length; i++) {
      final d = (strings[i] - midi).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}

/// Standard tunings. Chromatic is the free tier; presets are Pro.
const List<Instrument> kInstruments = [
  Instrument(id: 'chromatic', nameEn: 'Chromatic', nameZh: '半音', strings: [], free: true),
  Instrument(id: 'guitar', nameEn: 'Guitar', nameZh: '吉他', strings: [40, 45, 50, 55, 59, 64]), // E2 A2 D3 G3 B3 E4
  Instrument(id: 'ukulele', nameEn: 'Ukulele', nameZh: '尤克里里', strings: [67, 60, 64, 69]), // G4 C4 E4 A4 (re-entrant)
  Instrument(id: 'violin', nameEn: 'Violin', nameZh: '小提琴', strings: [55, 62, 69, 76]), // G3 D4 A4 E5
  Instrument(id: 'bass', nameEn: 'Bass', nameZh: '贝斯', strings: [28, 33, 38, 43]), // E1 A1 D2 G2
];

Instrument instrumentById(String id) =>
    kInstruments.firstWhere((i) => i.id == id, orElse: () => kInstruments.first);

/// Human string label like `E2` for buttons.
String stringLabel(int midi) => noteName(midi);
