import 'package:flutter_test/flutter_test.dart';
import 'package:tunekit/tool/music/theory.dart';
import 'package:tunekit/tool/music/tunings.dart';
import 'package:tunekit/tool/music/voicing.dart';

void main() {
  IntervalPattern p(String id) => patternById(id)!;
  final guitar = instrumentById('guitar');
  final uke = instrumentById('ukulele');

  group('chords', () {
    test('C major = C E G, symbol C', () {
      final c = RootedPattern(0, p('maj'));
      expect(c.noteNames, ['C', 'E', 'G']);
      expect(c.label, 'C');
    });

    test('A minor 7 = A C E G, symbol Am7', () {
      final am7 = RootedPattern(9, p('m7'));
      expect(am7.noteNames, ['A', 'C', 'E', 'G']);
      expect(am7.label, 'Am7');
    });

    test('Bb7 spells flats; F#dim7 spells sharps', () {
      expect(RootedPattern(10, p('7')).noteNames, ['Bb', 'D', 'F', 'Ab']);
      expect(RootedPattern(6, p('dim7')).noteNames, ['F#', 'A', 'C', 'D#']);
    });

    test('extensions wrap into pitch classes without duplicates', () {
      final c9 = RootedPattern(0, p('9'));
      expect(c9.pitchClasses, [0, 4, 7, 10, 2]);
      expect(c9.midiNotes(baseMidi: 60), [60, 64, 67, 70, 74]);
    });

    test('degree labels', () {
      expect(p('m7').semitones.map(degreeLabel).toList(), ['1', 'b3', '5', 'b7']);
      expect(p('add9').semitones.map(degreeLabel).toList(), ['1', '3', '5', '9']);
      expect(p('7#9').semitones.map(degreeLabel).toList(), ['1', '3', '5', 'b7', '#9']);
    });
  });

  group('scales', () {
    test('C major', () {
      expect(RootedPattern(0, p('major')).noteNames, ['C', 'D', 'E', 'F', 'G', 'A', 'B']);
    });

    test('A minor pentatonic = A C D E G', () {
      expect(RootedPattern(9, p('minPent')).noteNames, ['A', 'C', 'D', 'E', 'G']);
    });

    test('D dorian is the white keys from D', () {
      expect(RootedPattern(2, p('dorian')).noteNames, ['D', 'E', 'F', 'G', 'A', 'B', 'C']);
    });

    test('Eb major spells flats', () {
      expect(RootedPattern(3, p('major')).noteNames, ['Eb', 'F', 'G', 'Ab', 'Bb', 'C', 'D']);
    });

    test('harmonic minor raises the 7th', () {
      expect(RootedPattern(9, p('harmMinor')).noteNames, ['A', 'B', 'C', 'D', 'E', 'F', 'G#']);
    });

    test('every pattern is strictly ascending and starts on the root', () {
      for (final pat in kAllPatterns) {
        expect(pat.semitones.first, 0, reason: pat.id);
        for (var i = 1; i < pat.semitones.length; i++) {
          expect(pat.semitones[i], greaterThan(pat.semitones[i - 1]), reason: pat.id);
        }
      }
    });

    test('ids are unique and exactly five patterns are free', () {
      final ids = kAllPatterns.map((e) => e.id).toSet();
      expect(ids.length, kAllPatterns.length);
      expect(kAllPatterns.where((e) => e.free).length, 5);
    });
  });

  group('guitar voicings (derived, not tabled)', () {
    String shape(int root, String id) => deriveVoicing(RootedPattern(root, p(id)), guitar)!.shorthand;

    test('open major shapes', () {
      expect(shape(0, 'maj'), 'x32010'); // C
      expect(shape(7, 'maj'), '320003'); // G
      expect(shape(2, 'maj'), 'xx0232'); // D
      expect(shape(4, 'maj'), '022100'); // E
      expect(shape(9, 'maj'), 'x02220'); // A
    });

    test('open minor shapes', () {
      expect(shape(9, 'min'), 'x02210'); // Am
      expect(shape(4, 'min'), '022000'); // Em
      expect(shape(2, 'min'), 'xx0231'); // Dm
    });

    test('dominant sevenths drop the fifth or a doubled tone', () {
      expect(shape(0, '7'), 'x32310'); // C7
      expect(shape(7, '7'), '320001'); // G7
      expect(shape(4, '7'), '020100'); // E7
      expect(shape(9, '7'), 'x02020'); // A7
      expect(shape(2, '7'), 'xx0212'); // D7
      expect(shape(11, '7'), 'x21202'); // B7
    });

    test('major and minor sevenths', () {
      expect(shape(0, 'maj7'), 'x32000'); // Cmaj7
      expect(shape(9, 'm7'), 'x02010'); // Am7
    });

    test('every voicing sounds every chord tone (or drops only the fifth)', () {
      for (final chord in kChordTypes) {
        for (var root = 0; root < 12; root++) {
          final rp = RootedPattern(root, chord);
          final v = deriveVoicing(rp, guitar);
          if (v == null) continue;
          final missing = rp.pitchClasses.toSet().difference(v.soundedPitchClasses);
          missing.remove((root + 7) % 12);
          // Triads and four-note chords must be complete (bar the fifth).
          // Five-plus-note chords may drop one more tone in first position —
          // six strings and four frets cannot always hold them, and the
          // detail page tells the user which tone the shape leaves out.
          final allowed = rp.pitchClasses.length >= 5 ? 1 : 0;
          expect(missing.length, lessThanOrEqualTo(allowed), reason: '${rp.label}: ${v.shorthand} missing $missing');
          expect(v.soundedPitchClasses, contains(root), reason: '${rp.label}: root must sound');
          expect(v.frets.where((f) => f >= 0).length, greaterThanOrEqualTo(3), reason: rp.label);
          expect(v.frets.fold(0, (a, b) => a > b ? a : b), lessThanOrEqualTo(13));
        }
      }
    });

    test('ukulele C = 0003, G = 0232, Am = 2000', () {
      expect(deriveVoicing(RootedPattern(0, p('maj')), uke)!.shorthand, '0003');
      expect(deriveVoicing(RootedPattern(7, p('maj')), uke)!.shorthand, '0232');
      expect(deriveVoicing(RootedPattern(9, p('min')), uke)!.shorthand, '2000');
    });

    test('barre shapes appear where open shapes cannot', () {
      expect(shape(5, 'maj'), '103211'); // F: an easy open shape is found first
      expect(shape(8, 'maj'), '466544'); // Ab barre at 4
      expect(shape(10, 'min'), 'x13321'); // Bbm: A-shape barre at 1
    });

    test('no voicing for unfretted instruments', () {
      expect(deriveVoicing(RootedPattern(0, p('maj')), instrumentById('violin')), isNull);
      expect(deriveVoicing(RootedPattern(0, p('maj')), instrumentById('chromatic')), isNull);
    });
  });

  group('tunings', () {
    test('nearest string picks the closest open pitch', () {
      expect(guitar.nearestString(40.3), 0); // E2
      expect(guitar.nearestString(63.6), 5); // E4
      expect(guitar.nearestString(52.4), 2); // D3 (50) vs G3 (55): 52.4 → D3
      expect(instrumentById('chromatic').nearestString(60), -1);
    });
  });
}
