// Reference-fidelity test (PIPELINE G8c): every entry of our chord / scale
// dictionary must have exactly the interval set that tonal.js gives it.
//
// Expected values are the interval strings from tonaljs/tonal
// (packages/chord-type/data.ts and packages/scale-type/data.ts, MIT
// License, Copyright (c) 2015-2024 dani ferrer) and are turned into
// semitones here with tonal's own interval arithmetic
// (packages/pitch-interval/index.ts: SIZES / TYPES / qToAlt), rewritten in
// Dart. See REFERENCE.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:tunekit/tool/music/theory.dart';

/// Semitones of one tonal interval name like `3M`, `5d`, `9A`, `11P`.
int tonalSemitones(String name) {
  final m = RegExp(r'^(\d+)(d+|m|M|P|A+)$').firstMatch(name);
  if (m == null) throw ArgumentError('not a tonal interval: $name');
  final num = int.parse(m.group(1)!);
  final q = m.group(2)!;
  // pitch-interval: SIZES = [0, 2, 4, 5, 7, 9, 11], TYPES = "PMMPPMM"
  const sizes = [0, 2, 4, 5, 7, 9, 11];
  const types = 'PMMPPMM';
  final step = (num - 1) % 7;
  final perfectable = types[step] == 'P';
  final oct = (num - 1) ~/ 7;
  final int alt;
  if (q == 'M') {
    if (perfectable) throw ArgumentError('$name: M on a perfectable');
    alt = 0;
  } else if (q == 'P') {
    if (!perfectable) throw ArgumentError('$name: P on a majorable');
    alt = 0;
  } else if (q == 'm') {
    alt = -1;
  } else if (q.startsWith('A')) {
    alt = q.length;
  } else {
    // 'd', 'dd' ...: perfectable -> -n, majorable -> -(n+1)
    alt = perfectable ? -q.length : -(q.length + 1);
  }
  return sizes[step] + alt + 12 * oct;
}

List<int> tonalSet(String intervals) =>
    intervals.split(' ').map(tonalSemitones).toList();

void main() {
  test('tonal interval arithmetic reproduced', () {
    expect(tonalSemitones('1P'), 0);
    expect(tonalSemitones('3m'), 3);
    expect(tonalSemitones('3M'), 4);
    expect(tonalSemitones('5d'), 6);
    expect(tonalSemitones('5A'), 8);
    expect(tonalSemitones('7d'), 9);
    expect(tonalSemitones('7m'), 10);
    expect(tonalSemitones('9m'), 13);
    expect(tonalSemitones('9M'), 14);
    expect(tonalSemitones('9A'), 15);
    expect(tonalSemitones('11P'), 17);
    expect(tonalSemitones('11A'), 18);
    expect(tonalSemitones('13M'), 21);
  });

  // Our id -> (tonal intervals, tonal aliases that our symbol must appear
  // in). Data copied verbatim from tonal's dictionaries.
  const chords = <String, (String, String)>{
    'maj': ('1P 3M 5P', 'M ^  maj'),
    'min': ('1P 3m 5P', 'm min -'),
    'dim': ('1P 3m 5d', 'dim ° o'),
    'aug': ('1P 3M 5A', 'aug + +5 ^#5'),
    '5': ('1P 5P', '5'),
    'sus2': ('1P 2M 5P', 'sus2'),
    'sus4': ('1P 4P 5P', 'sus4 sus'),
    '7sus4': ('1P 4P 5P 7m', '7sus4 7sus'),
    '7': ('1P 3M 5P 7m', '7 dom'),
    'maj7': ('1P 3M 5P 7M', 'maj7 Δ ma7 M7 Maj7 ^7'),
    'm7': ('1P 3m 5P 7m', 'm7 min7 mi7 -7'),
    'mMaj7': ('1P 3m 5P 7M', 'm/ma7 m/maj7 mM7 mMaj7 m/M7 -Δ7 mΔ -^7 -maj7'),
    'dim7': ('1P 3m 5d 7d', 'dim7 °7 o7'),
    'm7b5': ('1P 3m 5d 7m', 'm7b5 ø -7b5 h7 h'),
    'aug7': ('1P 3M 5A 7m', '7#5 +7 7+ 7aug aug7'),
    '6': ('1P 3M 5P 6M', '6 add6 add13 M6'),
    'm6': ('1P 3m 5P 6M', 'm6 -6'),
    'add9': ('1P 3M 5P 9M', 'Madd9 2 add9 add2'),
    'madd9': ('1P 3m 5P 9M', 'madd9'),
    '9': ('1P 3M 5P 7m 9M', '9'),
    'maj9': ('1P 3M 5P 7M 9M', 'maj9 Δ9 ^9'),
    'm9': ('1P 3m 5P 7m 9M', 'm9 -9'),
    '69': ('1P 3M 5P 6M 9M', '6add9 6/9 69 M69'),
    '7b9': ('1P 3M 5P 7m 9m', '7b9'),
    '7#9': ('1P 3M 5P 7m 9A', '7#9'),
    '11': ('1P 5P 7m 9M 11P', '11'),
    '13': ('1P 3M 5P 7m 9M 13M', '13'),
    'maj7#11': ('1P 3M 5P 7M 11A', 'maj#4 Δ#4 Δ#11 M7#11 ^7#11 maj7#11'),
  };

  const scales = <String, String>{
    'major': '1P 2M 3M 4P 5P 6M 7M',
    'minor': '1P 2M 3m 4P 5P 6m 7m',
    'harmMinor': '1P 2M 3m 4P 5P 6m 7M',
    'melMinor': '1P 2M 3m 4P 5P 6M 7M',
    'majPent': '1P 2M 3M 5P 6M',
    'minPent': '1P 3m 4P 5P 7m',
    'blues': '1P 3m 4P 5d 5P 7m', // "minor blues", alias "blues"
    'majBlues': '1P 2M 3m 3M 5P 6M', // "major blues"
    'dorian': '1P 2M 3m 4P 5P 6M 7m',
    'phrygian': '1P 2m 3m 4P 5P 6m 7m',
    'lydian': '1P 2M 3M 4A 5P 6M 7M',
    'mixolydian': '1P 2M 3M 4P 5P 6M 7m',
    'locrian': '1P 2m 3m 4P 5d 6m 7m',
    'wholeTone': '1P 2M 3M 4A 5A 6A',
    'dimWH': '1P 2M 3m 4P 5d 6m 6M 7M', // "diminished" / "whole-half diminished"
    'dimHW': '1P 2m 3m 3M 4A 5P 6M 7m', // "half-whole diminished"
    'phrygDom': '1P 2m 3M 4P 5P 6m 7m', // "phrygian dominant"
    'hungMinor': '1P 2M 3m 4A 5P 6m 7M', // "hungarian minor"
    'dblHarm': '1P 2m 3M 4P 5P 6m 7M', // "double harmonic major"
    'chromatic': '1P 2m 2M 3m 3M 4P 5d 5P 6m 6M 7m 7M',
  };

  test('the tables cover every dictionary entry, nothing more', () {
    expect(kChordTypes.map((c) => c.id).toSet(), chords.keys.toSet());
    expect(kScaleTypes.map((s) => s.id).toSet(), scales.keys.toSet());
    expect(chords.length + scales.length, 48);
  });

  group('chord intervals == tonal', () {
    for (final entry in chords.entries) {
      test(entry.key, () {
        final ours = patternById(entry.key)!;
        expect(ours.isChord, isTrue);
        expect(ours.semitones, tonalSet(entry.value.$1),
            reason: '${entry.key}: tonal says ${entry.value.$1}');
      });
    }
  });

  group('chord symbol is a tonal alias', () {
    for (final entry in chords.entries) {
      test(entry.key, () {
        final ours = patternById(entry.key)!;
        final aliases = entry.value.$2.split(RegExp(r'\s+'));
        // Our major has an empty suffix (C, not CM); tonal's alias list for
        // major has no empty alias, "C" parses to it through tokenize().
        final symbol = ours.symbol.isEmpty ? 'M' : ours.symbol;
        expect(aliases, contains(symbol),
            reason: '${entry.key}: "$symbol" not in tonal aliases $aliases');
      });
    }
  });

  group('scale intervals == tonal', () {
    for (final entry in scales.entries) {
      test(entry.key, () {
        final ours = patternById(entry.key)!;
        expect(ours.isChord, isFalse);
        expect(ours.semitones, tonalSet(entry.value),
            reason: '${entry.key}: tonal says ${entry.value}');
      });
    }
  });

  test('chord-tone degree labels agree with tonal interval numbers', () {
    // degreeLabels must name the same scale degree tonal's interval does
    // (accidental aside): "9M" -> 9, "11A" -> 11, "5d" -> 5, "6M" -> 6,
    // and dim7's "7d" -> 7 (bb7), which a context-free lookup gets wrong.
    for (final entry in chords.entries) {
      final ours = patternById(entry.key)!;
      final names = entry.value.$1.split(' ');
      final labels = ours.degreeLabels;
      expect(labels.length, names.length, reason: entry.key);
      for (var i = 0; i < names.length; i++) {
        final tonalNum = int.parse(RegExp(r'^\d+').firstMatch(names[i])!.group(0)!);
        final label = labels[i];
        final ourNum = int.parse(label.replaceAll(RegExp(r'[^0-9]'), ''));
        expect(ourNum, tonalNum, reason: '${entry.key}: ${names[i]} vs $label');
      }
    }
  });
}
