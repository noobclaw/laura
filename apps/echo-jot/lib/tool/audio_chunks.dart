// Pure audio bookkeeping for the Whisper engine: WAV header parsing/writing,
// splitting a long recording into overlapping chunks, and merging the chunk
// transcripts back into one text. No Flutter, no I/O — everything here is
// unit-tested (test/whisper_logic_test.dart).
//
// Why chunk at all: whisper.cpp copes with long files by itself, but one
// monolithic call gives no usable progress, cannot be cancelled, and holds
// the whole recording's PCM in native memory at once. Chunks of ~60 s keep
// each call short; the overlap makes sure a word straddling a cut is heard
// in full by at least one chunk, and the merge assigns every timed segment
// to exactly one chunk so nothing is dropped or duplicated.

import 'dart:typed_data';

import 'transcript_text.dart' show isCjkText;

/// The parts of a WAV header the engine needs. Only PCM is supported.
class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Byte offset of the first audio sample in the file.
  final int dataOffset;

  /// Length of the audio payload in bytes.
  final int dataLength;

  int get bytesPerFrame => channels * (bitsPerSample ~/ 8);

  /// Number of sample frames (one frame = one sample per channel).
  int get frameCount => bytesPerFrame == 0 ? 0 : dataLength ~/ bytesPerFrame;

  Duration get duration => sampleRate == 0
      ? Duration.zero
      : Duration(microseconds: frameCount * 1000000 ~/ sampleRate);

  /// The exact layout whisper.cpp wants and the recorder is asked for; when
  /// a platform hands back something else the engine skips chunking and
  /// lets the plugin's converter handle the whole file.
  bool get isWhisperNative =>
      sampleRate == 16000 && channels == 1 && bitsPerSample == 16;
}

/// Parses a RIFF/WAVE header. [bytes] needs to hold at least the header
/// (the first few KB of the file is plenty). Throws [FormatException] for
/// anything that is not PCM WAV.
///
/// Walks the chunk list rather than assuming a 44-byte header: recorders on
/// both platforms emit extra chunks (LIST/fact) before `data`.
WavInfo parseWavHeader(Uint8List bytes, {int? fileLength}) {
  final bd = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      _fourcc(bytes, 0) != 'RIFF' ||
      _fourcc(bytes, 8) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  int? sampleRate;
  int? channels;
  int? bits;
  int? format;
  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = _fourcc(bytes, pos);
    final size = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      if (body + 16 > bytes.length) {
        throw const FormatException('truncated fmt chunk');
      }
      format = bd.getUint16(body, Endian.little);
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (format == null || channels == null || sampleRate == null ||
          bits == null) {
        throw const FormatException('data chunk before fmt chunk');
      }
      // WAVE_FORMAT_PCM (1) or WAVE_FORMAT_EXTENSIBLE (0xFFFE) wrapping PCM.
      if (format != 1 && format != 0xFFFE) {
        throw FormatException('unsupported WAV format tag $format');
      }
      if (bits != 16 && bits != 8 && bits != 24 && bits != 32) {
        throw FormatException('unsupported bit depth $bits');
      }
      // Streaming recorders write 0 or 0xFFFFFFFF as the data size and never
      // patch it; the real length is whatever follows the header.
      var length = size;
      if (fileLength != null) {
        final available = fileLength - body;
        if (length == 0 || length == 0xFFFFFFFF || length > available) {
          length = available < 0 ? 0 : available;
        }
      }
      return WavInfo(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bits,
        dataOffset: body,
        dataLength: length,
      );
    }
    // Chunks are word-aligned: an odd size is followed by a pad byte.
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}

/// A canonical 44-byte PCM WAV header for [dataLength] bytes of audio.
Uint8List wavHeader({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int dataLength,
}) {
  final header = Uint8List(44);
  final bd = ByteData.sublistView(header);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  _putFourcc(header, 0, 'RIFF');
  bd.setUint32(4, 36 + dataLength, Endian.little);
  _putFourcc(header, 8, 'WAVE');
  _putFourcc(header, 12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * blockAlign, Endian.little);
  bd.setUint16(32, blockAlign, Endian.little);
  bd.setUint16(34, bitsPerSample, Endian.little);
  _putFourcc(header, 36, 'data');
  bd.setUint32(40, dataLength, Endian.little);
  return header;
}

String _fourcc(Uint8List b, int at) =>
    String.fromCharCodes(b.sublist(at, at + 4));

void _putFourcc(Uint8List b, int at, String s) {
  for (var i = 0; i < 4; i++) {
    b[at + i] = s.codeUnitAt(i);
  }
}

/// One slice of the recording, in sample frames.
class ChunkPlan {
  const ChunkPlan({
    required this.index,
    required this.startFrame,
    required this.endFrame,
  });

  final int index;
  final int startFrame;

  /// Exclusive.
  final int endFrame;

  int get frameCount => endFrame - startFrame;
}

/// Default chunk length and overlap, in seconds. 60 s keeps one whisper.cpp
/// call to a few seconds on a phone; 5 s of overlap is longer than any word
/// and short enough that the duplicated work stays under 10%.
const int defaultChunkSeconds = 60;
const int defaultOverlapSeconds = 5;

/// Splits [totalFrames] into chunks of [chunkSeconds] with [overlapSeconds]
/// shared between neighbours. A recording that fits in one chunk yields
/// exactly one plan covering everything. A tail that would be shorter than
/// the overlap is already fully covered by the previous chunk and is not
/// emitted as a chunk of its own.
List<ChunkPlan> planChunks({
  required int totalFrames,
  required int sampleRate,
  int chunkSeconds = defaultChunkSeconds,
  int overlapSeconds = defaultOverlapSeconds,
}) {
  if (totalFrames <= 0) return const [];
  assert(chunkSeconds > overlapSeconds && overlapSeconds >= 0);
  final chunk = chunkSeconds * sampleRate;
  final overlap = overlapSeconds * sampleRate;
  final stride = chunk - overlap;
  final plans = <ChunkPlan>[];
  var start = 0;
  while (start < totalFrames) {
    final end = start + chunk < totalFrames ? start + chunk : totalFrames;
    plans.add(ChunkPlan(index: plans.length, startFrame: start, endFrame: end));
    if (end >= totalFrames) break;
    start += stride;
    // Whatever is left is inside the overlap of the chunk just planned.
    if (totalFrames - start <= overlap) break;
  }
  return plans;
}

/// One recognised phrase with its position in the *chunk* it came from.
class TimedSegment {
  const TimedSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  Duration get midpoint => Duration(
      microseconds: (start.inMicroseconds + end.inMicroseconds) ~/ 2);
}

/// What one chunk transcribed to, with its position in the recording.
class ChunkTranscript {
  const ChunkTranscript({
    required this.offset,
    required this.length,
    required this.text,
    this.segments,
  });

  /// Where the chunk starts in the full recording.
  final Duration offset;

  /// Length of the chunk's audio.
  final Duration length;

  /// Plain text of the chunk (used when [segments] is null).
  final String text;

  /// Timed segments, chunk-relative. Null when the engine gave none.
  final List<TimedSegment>? segments;
}

/// Merges chunk transcripts into one text.
///
/// With timed segments: every neighbouring pair shares an overlap window;
/// one cut line runs through its middle, and each segment goes to the chunk
/// on whose side of the line its midpoint falls. A word split by the chunk
/// edge lives in the overlap, so the chunk that heard it whole wins and the
/// half-word from the other chunk is discarded.
///
/// The two chunks do not segment the overlap identically (the later one
/// starts mid-speech), so the midpoint rule alone can put *both* versions of
/// a phrase on the wrong side and lose it. Hence a soft rule for the later
/// chunk: a segment before the cut is still kept unless its words already
/// appear in what the earlier chunk kept. Worst case is a visible duplicate
/// the user can delete — never a silently dropped phrase.
///
/// Without segments (engine gave none) the fallback trims the longest
/// repeated text across the seam.
String mergeChunkTranscripts(List<ChunkTranscript> chunks) {
  if (chunks.isEmpty) return '';
  if (chunks.length == 1) {
    final only = chunks.first;
    return only.segments == null
        ? only.text.trim()
        : joinSegmentTexts(_cleanSegments(only.segments!));
  }

  final allTimed = chunks.every((c) => c.segments != null);
  if (!allTimed) {
    var out = '';
    for (final c in chunks) {
      final text = c.segments == null
          ? c.text.trim()
          : joinSegmentTexts(_cleanSegments(c.segments!));
      out = _joinWithSeamTrim(out, text);
    }
    return out;
  }

  final kept = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    final c = chunks[i];
    // Absolute cut lines with the previous and the next chunk.
    final Duration? leftCut =
        i == 0 ? null : c.offset + _halfOverlap(chunks[i - 1], c);
    final Duration? rightCut = i == chunks.length - 1
        ? null
        : chunks[i + 1].offset + _halfOverlap(c, chunks[i + 1]);
    // What the previous chunk contributed near the seam, for the soft rule.
    final tail = _normalizedTail(kept);
    for (final s in _cleanSegments(c.segments!)) {
      final mid = c.offset + s.midpoint;
      if (leftCut != null && mid < leftCut && _coveredBy(tail, s.text)) {
        continue;
      }
      if (rightCut != null && mid >= rightCut) continue;
      kept.add(s.text);
    }
  }
  return joinSegmentTexts(kept.map((t) => TimedSegment(
        start: Duration.zero,
        end: Duration.zero,
        text: t,
      )));
}

/// The last few kept segments, normalised for containment checks.
String _normalizedTail(List<String> kept) {
  final from = kept.length > 3 ? kept.length - 3 : 0;
  return _normalize(kept.sublist(from).join(' '));
}

/// Lower-cased letters and digits only, so "Half." and "half" compare equal
/// and CJK text compares without punctuation.
String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// True when [text] is already present in [tail]. Fragments of one or two
/// characters are the cut-off halves of a word and count as covered too:
/// the other chunk heard the whole word.
bool _coveredBy(String tail, String text) {
  final n = _normalize(text);
  if (n.length <= 2) return true;
  return tail.contains(n);
}

Duration _halfOverlap(ChunkTranscript a, ChunkTranscript b) {
  final overlap = a.offset + a.length - b.offset;
  return Duration(
      microseconds: overlap.inMicroseconds <= 0 ? 0 : overlap.inMicroseconds ~/ 2);
}

/// Drops whisper's non-speech annotations and empty segments.
Iterable<TimedSegment> _cleanSegments(Iterable<TimedSegment> segs) =>
    segs.where((s) => !isNonSpeechArtifact(s.text));

/// True for segments whisper emits for silence or noise instead of words:
/// "[BLANK_AUDIO]", "(music)", "♪", "*laughs*", or nothing at all.
bool isNonSpeechArtifact(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (RegExp(r'^[\[\(（【][^\]\)）】]*[\]\)）】]$').hasMatch(t)) return true;
  if (RegExp(r'^\*[^*]*\*$').hasMatch(t)) return true;
  // Only punctuation / music symbols, no letters or ideographs.
  return !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t);
}

/// Joins segment texts the way whisper's own punctuation expects: CJK text
/// concatenates directly, Latin text gets a single space between segments.
/// Whisper punctuates by itself, so — unlike the system recognizer path —
/// no sentence terminators are inserted here; `finalizeTranscript` still
/// closes the last sentence.
String joinSegmentTexts(Iterable<TimedSegment> segments) {
  final buf = StringBuffer();
  for (final s in segments) {
    final t = s.text.trim();
    if (t.isEmpty) continue;
    if (buf.isNotEmpty) {
      final prev = buf.toString();
      final cjkSeam = isCjkText(prev[prev.length - 1]) || isCjkText(t[0]);
      if (!cjkSeam) buf.write(' ');
    }
    buf.write(t);
  }
  return buf.toString();
}

/// Fallback seam merge for untimed text: if the end of [a] repeats at the
/// start of [b] (the overlap was transcribed twice), the repeat is dropped
/// from [b]. Needs at least [minRepeat] characters of agreement so a common
/// word does not get swallowed by accident.
String _joinWithSeamTrim(String a, String b, {int minRepeat = 6}) {
  final left = a.trim();
  final right = b.trim();
  if (left.isEmpty) return right;
  if (right.isEmpty) return left;
  final cjk = isCjkText(left) || isCjkText(right);
  final max = left.length < right.length ? left.length : right.length;
  var best = 0;
  for (var n = max; n >= minRepeat; n--) {
    if (left.substring(left.length - n) == right.substring(0, n)) {
      best = n;
      break;
    }
  }
  final tail = right.substring(best).trimLeft();
  if (tail.isEmpty) return left;
  return cjk ? '$left$tail' : '$left $tail';
}
