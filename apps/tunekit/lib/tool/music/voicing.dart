/// Derives a playable voicing for a chord on a fretted instrument, so the
/// "play and check" mode knows which note each string should sound.
///
/// Algorithm (own design, not a lookup table). A *position* is a window of
/// four frets; the open position also allows open strings.
///   1. Bass: on instruments whose strings ascend in pitch (guitar, bass),
///      walk strings low to high and mute every string below the first one
///      that can play the root inside the window — the bass note of a
///      beginner voicing is the root. A re-entrant ukulele has no bass
///      string, so every string may sound.
///   2. On each remaining string take the lowest fret in the window whose
///      pitch class belongs to the chord.
///   3. If a chord tone is still missing, re-fret one string to supply it,
///      only stealing a tone that is doubled elsewhere or is the fifth (the
///      one chord tone every voicing may drop). C7 thus becomes x32310, not
///      the plain C shape.
///   4. Accept the open position (root on fret 0..3, fingers up to fret 4)
///      if it sounds at least four strings with full coverage (the fifth
///      may be dropped); otherwise slide a four-fret window up the neck with
///      the root under the barre finger — that yields the barre shapes
///      (Ab = 466544, Bbm = x13321).
/// Produces the textbook open shapes for C, G, D, E, A, Am, Em, Dm, G7, C7,
/// E7, A7, D7, B7, Cmaj7, Am7 — verified in test/theory_test.dart.
library;

import 'theory.dart';
import 'tunings.dart';

/// -1 = muted.
class Voicing {
  const Voicing(this.frets, this.strings);

  /// Fret per string (index = string, low to high), -1 for muted.
  final List<int> frets;

  /// Open MIDI pitch per string, same order.
  final List<int> strings;

  /// MIDI note sounded by string [i], or null when muted.
  int? midiAt(int i) => frets[i] < 0 ? null : strings[i] + frets[i];

  /// Number of strings that sound.
  int get soundingCount => frets.where((f) => f >= 0).length;

  /// `x32010`-style text (hyphenated past the 9th fret).
  String get shorthand => frets
      .map((f) => f < 0 ? 'x' : f.toString())
      .join(frets.any((f) => f > 9) ? '-' : '');

  /// Pitch classes this voicing actually sounds.
  Set<int> get soundedPitchClasses => {
        for (var s = 0; s < frets.length; s++)
          if (frets[s] >= 0) pitchClassOf(strings[s] + frets[s]),
      };
}

Voicing? deriveVoicing(RootedPattern chord, Instrument inst) {
  if (!inst.hasFrets || inst.strings.length < 3) return null;
  final tones = chord.pitchClasses.toSet();
  final fifth = (chord.root + 7) % 12;
  final strings = inst.strings;

  var ascending = true;
  for (var s = 1; s < strings.length; s++) {
    if (strings[s] <= strings[s - 1]) ascending = false;
  }

  bool good(Voicing v) {
    final missing = tones.difference(v.soundedPitchClasses)..remove(fifth);
    // A chord with more tones than strings can never be complete; ask only
    // for as many as fit.
    final slack = (tones.length - v.soundingCount).clamp(0, 12);
    return v.soundingCount >= 4 && missing.length <= slack;
  }

  Voicing? best;
  var bestScore = -1;
  for (var lo = 0; lo <= 9; lo++) {
    // Open position: the hand sits at the nut (root on fret 0..3) but a
    // finger may reach fret 4; up the neck the window is the barre + 3.
    final hi = lo == 0 ? 4 : lo + 3;
    final v = _attempt(chord, strings, tones, fifth, lo, hi, ascending);
    if (v == null) continue;
    if (good(v)) return v;
    final score = v.soundingCount * 10 - tones.difference(v.soundedPitchClasses).length * 15 - lo;
    if (score > bestScore) {
      bestScore = score;
      best = v;
    }
  }
  return best;
}

Voicing? _attempt(RootedPattern chord, List<int> strings, Set<int> tones, int fifth,
    int lo, int hi, bool ascending) {
  final n = strings.length;
  final frets = List<int>.filled(n, -1);
  final allowOpen = lo == 0;

  Iterable<int> candidates() sync* {
    for (var f = lo; f <= hi; f++) {
      yield f;
    }
  }

  // 1. Bass string.
  var bass = -1;
  final bassMax = allowOpen ? 3 : hi;
  if (ascending) {
    for (var s = 0; s < n && bass < 0; s++) {
      for (final f in candidates()) {
        if (f > bassMax) break;
        if (pitchClassOf(strings[s] + f) == chord.root) {
          bass = s;
          frets[s] = f;
          break;
        }
      }
    }
    if (bass < 0 || n - bass < 3) return null;
    // Up the neck the root sits under the barre finger, i.e. at the bottom
    // of the window; anything else is a stretch shape no beginner plays.
    if (lo > 0 && frets[bass] != lo) return null;
  }

  // 2. Lowest chord-tone fret on every string above the bass.
  for (var s = bass + 1; s < n; s++) {
    for (final f in candidates()) {
      if (tones.contains(pitchClassOf(strings[s] + f))) {
        frets[s] = f;
        break;
      }
    }
  }

  Map<int, int> counts() {
    final m = <int, int>{};
    for (var s = 0; s < n; s++) {
      if (frets[s] < 0) continue;
      final pc = pitchClassOf(strings[s] + frets[s]);
      m[pc] = (m[pc] ?? 0) + 1;
    }
    return m;
  }

  // 3. Cover missing tones by re-fretting one string per missing tone.
  for (final missing in tones.difference(counts().keys.toSet()).toList()) {
    var bestString = -1;
    var bestFret = 99;
    final have = counts();
    for (var s = bass + 1; s < n; s++) {
      for (var f = allowOpen ? 0 : lo; f <= hi + 1; f++) {
        if (pitchClassOf(strings[s] + f) != missing) continue;
        if (frets[s] >= 0) {
          final current = pitchClassOf(strings[s] + frets[s]);
          final droppable = current == fifth ||
              (have[current] ?? 0) > 1 ||
              !tones.contains(current);
          if (!droppable) break;
        }
        if (f < bestFret) {
          bestFret = f;
          bestString = s;
        }
        break;
      }
    }
    if (bestString >= 0) {
      frets[bestString] = bestFret;
      continue;
    }
    // No single re-fret works: try a swap. String s1 takes the missing
    // tone; the tone it gave up moves to another string s2 whose own tone
    // is droppable. Dadd9 thus becomes xx0252 (E moves from the top string
    // to the B string so the top string can play F#).
    final fLo = allowOpen ? 0 : lo;
    var done = false;
    for (var s1 = bass + 1; s1 < n && !done; s1++) {
      if (frets[s1] < 0) continue;
      final gaveUp = pitchClassOf(strings[s1] + frets[s1]);
      int? f1;
      for (var f = fLo; f <= hi + 1; f++) {
        if (pitchClassOf(strings[s1] + f) == missing) {
          f1 = f;
          break;
        }
      }
      if (f1 == null) continue;
      for (var s2 = bass + 1; s2 < n && !done; s2++) {
        if (s2 == s1 || frets[s2] < 0) continue;
        final current = pitchClassOf(strings[s2] + frets[s2]);
        final droppable = current == fifth || (have[current] ?? 0) > 1 || current == gaveUp;
        if (!droppable) continue;
        for (var f = fLo; f <= hi + 1; f++) {
          if (pitchClassOf(strings[s2] + f) == gaveUp) {
            frets[s1] = f1;
            frets[s2] = f;
            done = true;
            break;
          }
        }
      }
    }
  }

  return Voicing(frets, strings);
}
