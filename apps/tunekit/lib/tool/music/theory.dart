/// Music theory primitives: pitch classes, note names, intervals, and the
/// chord / scale dictionary.
///
/// Written from first principles (equal temperament + the standard interval
/// formulas). The dictionary below is a curated subset for a practice app:
/// what a guitarist, ukulele or piano learner actually drills, not every
/// altered jazz voicing. Every entry carries a zh + en display name.
library;

import 'dart:math' as math;

/// Sharp spellings, index = pitch class (0 = C).
const List<String> kSharpNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// Flat spellings, index = pitch class.
const List<String> kFlatNames = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// Solfège-style Chinese note reading used alongside the letter name
/// (C = 1/do …). Only for the natural notes; accidentals keep the letter.
const List<String> kZhDegreeNames = [
  'do', '', 're', '', 'mi', 'fa', '', 'sol', '', 'la', '', 'si',
];

/// Roots that prefer flat spelling for their chord/scale tones. Beyond this
/// the sharp spelling is the one learners see on most charts.
const Set<int> kFlatRoots = {1, 3, 5, 8, 10}; // Db Eb F Ab Bb

/// Frequency of a MIDI note under 12-TET with the given A4 reference.
double midiToFrequency(double midi, {double a4 = 440.0}) =>
    a4 * math.pow(2.0, (midi - 69.0) / 12.0);

/// Fractional MIDI number of a frequency (69.0 = A4 exactly).
double frequencyToMidi(double hz, {double a4 = 440.0}) =>
    69.0 + 12.0 * (math.log(hz / a4) / math.ln2);

/// The pitch class (0..11) of a MIDI number.
int pitchClassOf(int midi) => ((midi % 12) + 12) % 12;

/// Scientific octave number of a MIDI note (C4 = 60).
int octaveOf(int midi) => (midi ~/ 12) - 1;

/// Letter name of a MIDI note, e.g. `A4`, `F#2`.
String noteName(int midi, {bool flats = false}) =>
    '${(flats ? kFlatNames : kSharpNames)[pitchClassOf(midi)]}${octaveOf(midi)}';

/// Letter name without the octave.
String pitchClassName(int pc, {bool flats = false}) =>
    (flats ? kFlatNames : kSharpNames)[((pc % 12) + 12) % 12];

/// A named interval structure (chord or scale type).
class IntervalPattern {
  const IntervalPattern({
    required this.id,
    required this.semitones,
    required this.nameEn,
    required this.nameZh,
    required this.symbol,
    required this.group,
    this.free = false,
  });

  /// Stable key used in persistence and tests.
  final String id;

  /// Semitone offsets from the root, ascending. Chord extensions may exceed
  /// 12 (a ninth is 14).
  final List<int> semitones;
  final String nameEn;
  final String nameZh;

  /// Chord symbol suffix (`m7`) or scale short label.
  final String symbol;
  final PatternGroup group;

  /// Included in the free tier.
  final bool free;

  bool get isChord => group.isChord;

  /// Pitch classes (0..11) relative to the root, deduplicated in order.
  List<int> get relativePitchClasses {
    final seen = <int>{};
    final out = <int>[];
    for (final s in semitones) {
      final pc = s % 12;
      if (seen.add(pc)) out.add(pc);
    }
    return out;
  }
}

enum PatternGroup {
  triads(true),
  sevenths(true),
  extended(true),
  suspended(true),
  scalesBasic(false),
  scalesPentatonic(false),
  scalesModes(false),
  scalesExotic(false);

  const PatternGroup(this.isChord);
  final bool isChord;
}

// Chord types. The semitone lists are the interval formulas themselves
// (major third = 4, perfect fifth = 7, minor seventh = 10, ...).
const List<IntervalPattern> kChordTypes = [
  IntervalPattern(id: 'maj', semitones: [0, 4, 7], nameEn: 'Major', nameZh: '大三和弦', symbol: '', group: PatternGroup.triads, free: true),
  IntervalPattern(id: 'min', semitones: [0, 3, 7], nameEn: 'Minor', nameZh: '小三和弦', symbol: 'm', group: PatternGroup.triads, free: true),
  IntervalPattern(id: 'dim', semitones: [0, 3, 6], nameEn: 'Diminished', nameZh: '减三和弦', symbol: 'dim', group: PatternGroup.triads),
  IntervalPattern(id: 'aug', semitones: [0, 4, 8], nameEn: 'Augmented', nameZh: '增三和弦', symbol: 'aug', group: PatternGroup.triads),
  IntervalPattern(id: '5', semitones: [0, 7], nameEn: 'Power chord', nameZh: '强力和弦', symbol: '5', group: PatternGroup.triads),
  IntervalPattern(id: 'sus2', semitones: [0, 2, 7], nameEn: 'Suspended 2nd', nameZh: '挂二和弦', symbol: 'sus2', group: PatternGroup.suspended),
  IntervalPattern(id: 'sus4', semitones: [0, 5, 7], nameEn: 'Suspended 4th', nameZh: '挂四和弦', symbol: 'sus4', group: PatternGroup.suspended),
  IntervalPattern(id: '7sus4', semitones: [0, 5, 7, 10], nameEn: 'Seventh suspended 4th', nameZh: '属七挂四', symbol: '7sus4', group: PatternGroup.suspended),
  IntervalPattern(id: '7', semitones: [0, 4, 7, 10], nameEn: 'Dominant 7th', nameZh: '属七和弦', symbol: '7', group: PatternGroup.sevenths, free: true),
  IntervalPattern(id: 'maj7', semitones: [0, 4, 7, 11], nameEn: 'Major 7th', nameZh: '大七和弦', symbol: 'maj7', group: PatternGroup.sevenths),
  IntervalPattern(id: 'm7', semitones: [0, 3, 7, 10], nameEn: 'Minor 7th', nameZh: '小七和弦', symbol: 'm7', group: PatternGroup.sevenths),
  IntervalPattern(id: 'mMaj7', semitones: [0, 3, 7, 11], nameEn: 'Minor–major 7th', nameZh: '小大七和弦', symbol: 'mMaj7', group: PatternGroup.sevenths),
  IntervalPattern(id: 'dim7', semitones: [0, 3, 6, 9], nameEn: 'Diminished 7th', nameZh: '减七和弦', symbol: 'dim7', group: PatternGroup.sevenths),
  IntervalPattern(id: 'm7b5', semitones: [0, 3, 6, 10], nameEn: 'Half-diminished', nameZh: '半减七和弦', symbol: 'm7b5', group: PatternGroup.sevenths),
  IntervalPattern(id: 'aug7', semitones: [0, 4, 8, 10], nameEn: 'Augmented 7th', nameZh: '增七和弦', symbol: 'aug7', group: PatternGroup.sevenths),
  IntervalPattern(id: '6', semitones: [0, 4, 7, 9], nameEn: 'Major 6th', nameZh: '大六和弦', symbol: '6', group: PatternGroup.sevenths),
  IntervalPattern(id: 'm6', semitones: [0, 3, 7, 9], nameEn: 'Minor 6th', nameZh: '小六和弦', symbol: 'm6', group: PatternGroup.sevenths),
  IntervalPattern(id: 'add9', semitones: [0, 4, 7, 14], nameEn: 'Add 9', nameZh: '加九和弦', symbol: 'add9', group: PatternGroup.extended),
  IntervalPattern(id: 'madd9', semitones: [0, 3, 7, 14], nameEn: 'Minor add 9', nameZh: '小加九和弦', symbol: 'madd9', group: PatternGroup.extended),
  IntervalPattern(id: '9', semitones: [0, 4, 7, 10, 14], nameEn: 'Dominant 9th', nameZh: '属九和弦', symbol: '9', group: PatternGroup.extended),
  IntervalPattern(id: 'maj9', semitones: [0, 4, 7, 11, 14], nameEn: 'Major 9th', nameZh: '大九和弦', symbol: 'maj9', group: PatternGroup.extended),
  IntervalPattern(id: 'm9', semitones: [0, 3, 7, 10, 14], nameEn: 'Minor 9th', nameZh: '小九和弦', symbol: 'm9', group: PatternGroup.extended),
  IntervalPattern(id: '69', semitones: [0, 4, 7, 9, 14], nameEn: 'Six-nine', nameZh: '六九和弦', symbol: '6/9', group: PatternGroup.extended),
  IntervalPattern(id: '7b9', semitones: [0, 4, 7, 10, 13], nameEn: 'Dominant 7th flat 9', nameZh: '属七降九', symbol: '7b9', group: PatternGroup.extended),
  IntervalPattern(id: '7#9', semitones: [0, 4, 7, 10, 15], nameEn: 'Dominant 7th sharp 9', nameZh: '属七升九', symbol: '7#9', group: PatternGroup.extended),
  IntervalPattern(id: '11', semitones: [0, 7, 10, 14, 17], nameEn: 'Dominant 11th', nameZh: '属十一和弦', symbol: '11', group: PatternGroup.extended),
  IntervalPattern(id: '13', semitones: [0, 4, 7, 10, 14, 21], nameEn: 'Dominant 13th', nameZh: '属十三和弦', symbol: '13', group: PatternGroup.extended),
  IntervalPattern(id: 'maj7#11', semitones: [0, 4, 7, 11, 18], nameEn: 'Major 7th sharp 11', nameZh: '大七升十一', symbol: 'maj7#11', group: PatternGroup.extended),
];

// Scale types. Step formulas: major = W W H W W W H, etc.
const List<IntervalPattern> kScaleTypes = [
  IntervalPattern(id: 'major', semitones: [0, 2, 4, 5, 7, 9, 11], nameEn: 'Major (Ionian)', nameZh: '大调音阶(伊奥尼亚)', symbol: 'major', group: PatternGroup.scalesBasic, free: true),
  IntervalPattern(id: 'minor', semitones: [0, 2, 3, 5, 7, 8, 10], nameEn: 'Natural minor (Aeolian)', nameZh: '自然小调(爱奥利亚)', symbol: 'minor', group: PatternGroup.scalesBasic),
  IntervalPattern(id: 'harmMinor', semitones: [0, 2, 3, 5, 7, 8, 11], nameEn: 'Harmonic minor', nameZh: '和声小调', symbol: 'harm. minor', group: PatternGroup.scalesBasic),
  IntervalPattern(id: 'melMinor', semitones: [0, 2, 3, 5, 7, 9, 11], nameEn: 'Melodic minor (asc.)', nameZh: '旋律小调(上行)', symbol: 'mel. minor', group: PatternGroup.scalesBasic),
  IntervalPattern(id: 'majPent', semitones: [0, 2, 4, 7, 9], nameEn: 'Major pentatonic', nameZh: '大调五声音阶', symbol: 'maj. pent.', group: PatternGroup.scalesPentatonic),
  IntervalPattern(id: 'minPent', semitones: [0, 3, 5, 7, 10], nameEn: 'Minor pentatonic', nameZh: '小调五声音阶', symbol: 'min. pent.', group: PatternGroup.scalesPentatonic, free: true),
  IntervalPattern(id: 'blues', semitones: [0, 3, 5, 6, 7, 10], nameEn: 'Blues (minor)', nameZh: '布鲁斯音阶', symbol: 'blues', group: PatternGroup.scalesPentatonic),
  IntervalPattern(id: 'majBlues', semitones: [0, 2, 3, 4, 7, 9], nameEn: 'Major blues', nameZh: '大调布鲁斯', symbol: 'maj. blues', group: PatternGroup.scalesPentatonic),
  IntervalPattern(id: 'dorian', semitones: [0, 2, 3, 5, 7, 9, 10], nameEn: 'Dorian', nameZh: '多利亚调式', symbol: 'dorian', group: PatternGroup.scalesModes),
  IntervalPattern(id: 'phrygian', semitones: [0, 1, 3, 5, 7, 8, 10], nameEn: 'Phrygian', nameZh: '弗里几亚调式', symbol: 'phrygian', group: PatternGroup.scalesModes),
  IntervalPattern(id: 'lydian', semitones: [0, 2, 4, 6, 7, 9, 11], nameEn: 'Lydian', nameZh: '利底亚调式', symbol: 'lydian', group: PatternGroup.scalesModes),
  IntervalPattern(id: 'mixolydian', semitones: [0, 2, 4, 5, 7, 9, 10], nameEn: 'Mixolydian', nameZh: '混合利底亚调式', symbol: 'mixolydian', group: PatternGroup.scalesModes),
  IntervalPattern(id: 'locrian', semitones: [0, 1, 3, 5, 6, 8, 10], nameEn: 'Locrian', nameZh: '洛克里亚调式', symbol: 'locrian', group: PatternGroup.scalesModes),
  IntervalPattern(id: 'wholeTone', semitones: [0, 2, 4, 6, 8, 10], nameEn: 'Whole tone', nameZh: '全音阶', symbol: 'whole tone', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'dimWH', semitones: [0, 2, 3, 5, 6, 8, 9, 11], nameEn: 'Diminished (whole–half)', nameZh: '减音阶(全半)', symbol: 'dim. W-H', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'dimHW', semitones: [0, 1, 3, 4, 6, 7, 9, 10], nameEn: 'Diminished (half–whole)', nameZh: '减音阶(半全)', symbol: 'dim. H-W', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'phrygDom', semitones: [0, 1, 4, 5, 7, 8, 10], nameEn: 'Phrygian dominant', nameZh: '弗里几亚属调式', symbol: 'phryg. dom.', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'hungMinor', semitones: [0, 2, 3, 6, 7, 8, 11], nameEn: 'Hungarian minor', nameZh: '匈牙利小调', symbol: 'hung. minor', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'dblHarm', semitones: [0, 1, 4, 5, 7, 8, 11], nameEn: 'Double harmonic', nameZh: '双和声音阶', symbol: 'dbl. harm.', group: PatternGroup.scalesExotic),
  IntervalPattern(id: 'chromatic', semitones: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], nameEn: 'Chromatic', nameZh: '半音阶', symbol: 'chromatic', group: PatternGroup.scalesExotic),
];

List<IntervalPattern> get kAllPatterns => [...kChordTypes, ...kScaleTypes];

IntervalPattern? patternById(String id) {
  for (final p in kAllPatterns) {
    if (p.id == id) return p;
  }
  return null;
}

/// A pattern rooted on a concrete pitch class: "A minor pentatonic", "G7".
class RootedPattern {
  const RootedPattern(this.root, this.pattern);

  /// Pitch class 0..11.
  final int root;
  final IntervalPattern pattern;

  bool get useFlats => kFlatRoots.contains(root);

  String get rootName => pitchClassName(root, flats: useFlats);

  /// Chord symbol like `Am7`, or scale label like `A minor pentatonic`.
  String get label => pattern.isChord
      ? '$rootName${pattern.symbol}'
      : '$rootName ${pattern.symbol}';

  /// Pitch classes of every tone, root first.
  List<int> get pitchClasses =>
      pattern.relativePitchClasses.map((s) => (root + s) % 12).toList();

  /// Spelled note names, root first.
  List<String> get noteNames =>
      pitchClasses.map((pc) => pitchClassName(pc, flats: useFlats)).toList();

  /// Absolute MIDI notes starting at [baseMidi] for the root, ascending in
  /// pattern order (extensions land in the next octave).
  List<int> midiNotes({int baseMidi = 60}) {
    final rootMidi = baseMidi - pitchClassOf(baseMidi) + root;
    final start = rootMidi < baseMidi ? rootMidi + 12 : rootMidi;
    return pattern.semitones.map((s) => start + s).toList();
  }

  bool contains(int pitchClass) =>
      pitchClasses.contains(((pitchClass % 12) + 12) % 12);
}

/// Degree label of a chord tone relative to its root (`1`, `b3`, `5`, `b7`,
/// `9`). Used on diagrams and in the theory quiz.
String degreeLabel(int semitone) {
  const names = {
    0: '1', 1: 'b9', 2: '9', 3: 'b3', 4: '3', 5: '11', 6: 'b5', 7: '5',
    8: '#5', 9: '13', 10: 'b7', 11: '7',
  };
  if (semitone >= 12) {
    const upper = {13: 'b9', 14: '9', 15: '#9', 17: '11', 18: '#11', 21: '13'};
    return upper[semitone] ?? names[semitone % 12] ?? '';
  }
  // Inside the octave, 2/5/9 semitones read as chord-scale degrees.
  const inOctave = {2: '2', 5: '4', 9: '6'};
  return inOctave[semitone] ?? names[semitone] ?? '';
}

/// Scale-degree label for scales (`1`..`7`, with accidentals relative to the
/// major scale).
String scaleDegreeLabel(int semitone) {
  const table = {
    0: '1', 1: 'b2', 2: '2', 3: 'b3', 4: '3', 5: '4', 6: '#4', 7: '5',
    8: 'b6', 9: '6', 10: 'b7', 11: '7',
  };
  return table[semitone % 12] ?? '';
}
