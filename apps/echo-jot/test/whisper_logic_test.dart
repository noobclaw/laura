import 'dart:math' as math;
import 'dart:typed_data';

import 'package:echo_jot/tool/audio_chunks.dart';
import 'package:echo_jot/tool/whisper_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('whisperLanguageCode', () {
    test('maps the picker tags to whisper codes', () {
      expect(whisperLanguageCode('zh-CN'), 'zh');
      expect(whisperLanguageCode('zh-TW'), 'zh');
      expect(whisperLanguageCode('en-US'), 'en');
      expect(whisperLanguageCode('en-GB'), 'en');
      expect(whisperLanguageCode('ja-JP'), 'ja');
      expect(whisperLanguageCode('ko-KR'), 'ko');
      expect(whisperLanguageCode('de-DE'), 'de');
      expect(whisperLanguageCode('fr-FR'), 'fr');
      expect(whisperLanguageCode('es-ES'), 'es');
    });

    test('auto, empty and unknown tags become auto', () {
      expect(whisperLanguageCode('auto'), 'auto');
      expect(whisperLanguageCode(''), 'auto');
      expect(whisperLanguageCode('   '), 'auto');
      expect(whisperLanguageCode('xx-YY'), 'auto');
    });

    test('tolerates underscores, case and legacy codes', () {
      expect(whisperLanguageCode('ZH_cn'), 'zh');
      expect(whisperLanguageCode('iw-IL'), 'he');
      expect(whisperLanguageCode('in-ID'), 'id');
      expect(whisperLanguageCode('yue'), 'yue');
    });
  });

  group('whisperInitialPrompt', () {
    test('steers Chinese script, nothing else', () {
      expect(whisperInitialPrompt('zh-CN'), '以下是普通话的句子。');
      expect(whisperInitialPrompt('zh'), '以下是普通话的句子。');
      expect(whisperInitialPrompt('zh-TW'), '以下是繁體中文的句子。');
      expect(whisperInitialPrompt('zh-Hant-HK'), '以下是繁體中文的句子。');
      expect(whisperInitialPrompt('en-US'), isNull);
      expect(whisperInitialPrompt('auto'), isNull);
    });
  });

  group('WAV header', () {
    test('round-trips through wavHeader / parseWavHeader', () {
      final header = wavHeader(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataLength: 32000,
      );
      final info = parseWavHeader(header, fileLength: 44 + 32000);
      expect(info.sampleRate, 16000);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
      expect(info.dataOffset, 44);
      expect(info.dataLength, 32000);
      expect(info.frameCount, 16000);
      expect(info.duration, const Duration(seconds: 1));
      expect(info.isWhisperNative, isTrue);
    });

    test('walks past extra chunks before data', () {
      final head = BytesBuilder();
      final base = wavHeader(
          sampleRate: 44100, channels: 2, bitsPerSample: 16, dataLength: 8);
      head.add(base.sublist(0, 36)); // RIFF + fmt
      // A LIST chunk of odd size (3) followed by its pad byte.
      head.add('LIST'.codeUnits);
      head.add((ByteData(4)..setUint32(0, 3, Endian.little)).buffer.asUint8List());
      head.add([1, 2, 3, 0]);
      head.add(base.sublist(36)); // data chunk header
      head.add(List.filled(8, 0));
      final bytes = head.toBytes();
      final info = parseWavHeader(bytes, fileLength: bytes.length);
      expect(info.sampleRate, 44100);
      expect(info.channels, 2);
      expect(info.dataOffset, 36 + 12 + 8);
      expect(info.dataLength, 8);
      expect(info.isWhisperNative, isFalse);
    });

    test('streaming header with 0 data size uses the file length', () {
      final header = wavHeader(
          sampleRate: 16000, channels: 1, bitsPerSample: 16, dataLength: 0);
      final info = parseWavHeader(header, fileLength: 44 + 4000);
      expect(info.dataLength, 4000);
    });

    test('rejects non-WAV bytes', () {
      expect(() => parseWavHeader(Uint8List(10)), throwsFormatException);
      expect(() => parseWavHeader(Uint8List.fromList('RIFFxxxxWAVE'.codeUnits)),
          throwsFormatException);
    });
  });

  group('planChunks', () {
    const sr = 16000;

    test('short recording is one chunk', () {
      final plans = planChunks(totalFrames: 30 * sr, sampleRate: sr);
      expect(plans.length, 1);
      expect(plans.single.startFrame, 0);
      expect(plans.single.endFrame, 30 * sr);
    });

    test('exactly one chunk long is still one chunk', () {
      final plans = planChunks(totalFrames: 60 * sr, sampleRate: sr);
      expect(plans.length, 1);
    });

    test('empty recording yields nothing', () {
      expect(planChunks(totalFrames: 0, sampleRate: sr), isEmpty);
    });

    test('long recording overlaps by the configured amount', () {
      final plans = planChunks(totalFrames: 150 * sr, sampleRate: sr);
      expect(plans.map((p) => p.index), [0, 1, 2]);
      expect(plans[0].startFrame, 0);
      expect(plans[0].endFrame, 60 * sr);
      expect(plans[1].startFrame, 55 * sr);
      expect(plans[1].endFrame, 115 * sr);
      expect(plans[2].startFrame, 110 * sr);
      expect(plans[2].endFrame, 150 * sr);
    });

    test('a tail inside the overlap is not a chunk of its own', () {
      // 60 s chunk, 5 s overlap: 63 s leaves a 3 s tail already covered.
      final plans = planChunks(totalFrames: 63 * sr, sampleRate: sr);
      expect(plans.length, 2);
      expect(plans[1].endFrame, 63 * sr);
      final plansCovered = planChunks(totalFrames: 60 * sr + 100, sampleRate: sr);
      expect(plansCovered.length, 2);
      // 5 s tail is exactly the overlap → dropped: the first chunk heard it.
      final edge = planChunks(totalFrames: 60 * sr, sampleRate: sr, chunkSeconds: 55);
      expect(edge.length, 2);
    });

    test('every frame is covered and neighbours overlap', () {
      final plans = planChunks(totalFrames: 1000 * sr + 17, sampleRate: sr);
      expect(plans.first.startFrame, 0);
      expect(plans.last.endFrame, 1000 * sr + 17);
      for (var i = 1; i < plans.length; i++) {
        expect(plans[i].startFrame, lessThan(plans[i - 1].endFrame));
        expect(plans[i].startFrame, greaterThan(plans[i - 1].startFrame));
      }
    });
  });

  group('mergeChunkTranscripts', () {
    TimedSegment seg(double from, double to, String text) => TimedSegment(
          start: Duration(milliseconds: (from * 1000).round()),
          end: Duration(milliseconds: (to * 1000).round()),
          text: text,
        );

    test('single chunk joins its segments', () {
      final out = mergeChunkTranscripts([
        ChunkTranscript(
          offset: Duration.zero,
          length: const Duration(seconds: 10),
          text: 'ignored',
          segments: [seg(0, 4, ' Buy milk.'), seg(4, 9, 'Call the dentist.')],
        ),
      ]);
      expect(out, 'Buy milk. Call the dentist.');
    });

    test('CJK segments concatenate without spaces', () {
      final out = mergeChunkTranscripts([
        ChunkTranscript(
          offset: Duration.zero,
          length: const Duration(seconds: 10),
          text: '',
          segments: [seg(0, 4, '买牛奶。'), seg(4, 9, '然后去银行。')],
        ),
      ]);
      expect(out, '买牛奶。然后去银行。');
    });

    test('overlap segments are assigned to exactly one chunk', () {
      // Chunk A: 0–60 s, chunk B: 55–115 s. Overlap 55–60, cut line at 57.5.
      final a = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [
          seg(0, 30, 'first half.'),
          seg(30, 56, 'second half.'),
          seg(56, 60, 'straddling the'), // cut word: midpoint 58 → B's side
        ],
      );
      final b = ChunkTranscript(
        offset: const Duration(seconds: 55),
        length: const Duration(seconds: 60),
        text: '',
        segments: [
          seg(0, 1.5, 'half.'), // tail of A's phrase: midpoint 55.75 → A's side
          seg(1.5, 6, 'straddling the edge.'), // midpoint 58.75 → kept
          seg(6, 60, 'and the rest.'),
        ],
      );
      expect(mergeChunkTranscripts([a, b]),
          'first half. second half. straddling the edge. and the rest.');
    });

    test('three chunks keep every middle segment once', () {
      final chunks = [
        ChunkTranscript(
          offset: Duration.zero,
          length: const Duration(seconds: 60),
          text: '',
          segments: [seg(0, 50, 'one.'), seg(57, 60, 'cut')],
        ),
        ChunkTranscript(
          offset: const Duration(seconds: 55),
          length: const Duration(seconds: 60),
          text: '',
          segments: [seg(2, 5, 'cut two.'), seg(5, 58, 'three.'), seg(58, 60, 'x')],
        ),
        ChunkTranscript(
          offset: const Duration(seconds: 110),
          length: const Duration(seconds: 30),
          text: '',
          segments: [seg(0, 4, 'x four.'), seg(4, 30, 'five.')],
        ),
      ];
      expect(mergeChunkTranscripts(chunks), 'one. cut two. three. x four. five.');
    });

    test('a phrase both chunks place before the cut is kept once', () {
      // Consistent segmentation: both chunks heard "half." at 55–56.5 s.
      final a = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [seg(0, 55, 'the first'), seg(55, 56.5, 'half.')],
      );
      final b = ChunkTranscript(
        offset: const Duration(seconds: 55),
        length: const Duration(seconds: 30),
        text: '',
        segments: [seg(0, 1.5, 'half.'), seg(3, 20, 'and the rest.')],
      );
      expect(mergeChunkTranscripts([a, b]), 'the first half. and the rest.');
    });

    test('a phrase only the later chunk heard whole survives the cut', () {
      // Chunk A ends on a cut-off fragment; chunk B's full phrase sits
      // before the cut line but is not covered by A's kept text.
      final a = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [seg(0, 56, '买牛奶。'), seg(58, 60, '然')],
      );
      final b = ChunkTranscript(
        offset: const Duration(seconds: 55),
        length: const Duration(seconds: 30),
        text: '',
        segments: [seg(0, 2, '然后去银行。'), seg(4, 10, '取钱。')],
      );
      expect(mergeChunkTranscripts([a, b]), '买牛奶。然后去银行。取钱。');
    });

    test('non-speech artifacts are dropped', () {
      final out = mergeChunkTranscripts([
        ChunkTranscript(
          offset: Duration.zero,
          length: const Duration(seconds: 10),
          text: '',
          segments: [
            seg(0, 2, '[BLANK_AUDIO]'),
            seg(2, 5, '(music)'),
            seg(5, 6, '♪'),
            seg(6, 7, '*laughs*'),
            seg(7, 9, 'real words'),
            seg(9, 10, '   '),
          ],
        ),
      ]);
      expect(out, 'real words');
    });

    test('untimed chunks trim the repeated seam', () {
      final out = mergeChunkTranscripts([
        const ChunkTranscript(
          offset: Duration.zero,
          length: Duration(seconds: 60),
          text: 'we should go to the market tomorrow morning',
        ),
        const ChunkTranscript(
          offset: Duration(seconds: 55),
          length: Duration(seconds: 20),
          text: 'tomorrow morning and buy eggs',
        ),
      ]);
      expect(out, 'we should go to the market tomorrow morning and buy eggs');
    });

    test('untimed CJK chunks join without a space', () {
      final out = mergeChunkTranscripts([
        const ChunkTranscript(
          offset: Duration.zero,
          length: Duration(seconds: 60),
          text: '明天上午去银行取钱',
        ),
        const ChunkTranscript(
          offset: Duration(seconds: 55),
          length: Duration(seconds: 20),
          text: '然后买菜',
        ),
      ]);
      expect(out, '明天上午去银行取钱然后买菜');
    });

    test('empty input is empty', () {
      expect(mergeChunkTranscripts(const []), '');
    });
  });

  group('isNonSpeechArtifact', () {
    test('keeps sentences that merely contain brackets', () {
      expect(isNonSpeechArtifact('call Bob (the plumber) today'), isFalse);
      expect(isNonSpeechArtifact('买牛奶(两盒)'), isFalse);
    });
    test('flags bracket-only and symbol-only text', () {
      expect(isNonSpeechArtifact('[BLANK_AUDIO]'), isTrue);
      expect(isNonSpeechArtifact('（音乐）'), isTrue);
      expect(isNonSpeechArtifact('...'), isTrue);
      expect(isNonSpeechArtifact(''), isTrue);
    });
    test('special tokens alone are an artifact', () {
      expect(isNonSpeechArtifact('[_BEG_]'), isTrue);
      expect(isNonSpeechArtifact('[_TT_450][_EOT_]'), isTrue);
    });
  });

  group('stripSpecialTokens', () {
    // Spellings from whisper_token_to_str (src/whisper.cpp) and the raw
    // vocabulary; none of them may survive into a note.
    test('removes whisper.cpp special-token spellings', () {
      expect(stripSpecialTokens('[_BEG_] hello world[_TT_450]'), ' hello world');
      expect(stripSpecialTokens('[_SOT_][_LANG_zh]买牛奶[_EOT_]'), '买牛奶');
      expect(stripSpecialTokens('[_extra_token_50364]x'), 'x');
      expect(stripSpecialTokens('<|startoftranscript|><|zh|>你好<|endoftext|>'),
          '你好');
    });
    test('leaves ordinary brackets alone', () {
      expect(stripSpecialTokens('a [note] and (aside)'), 'a [note] and (aside)');
      expect(stripSpecialTokens('[BLANK_AUDIO]'), '[BLANK_AUDIO]');
    });
    test('merge output never contains special tokens', () {
      final out = mergeChunkTranscripts([
        const ChunkTranscript(
          offset: Duration.zero,
          length: Duration(seconds: 5),
          text: '[_BEG_] plain text [_TT_250]',
        ),
      ]);
      expect(out, 'plain text');
    });
  });

  // -------------------------------------------------------------------------
  // Energy VAD: numbers hand-derived from whisper.cpp examples/common.cpp
  // (`high_pass_filter`, `vad_simple`), sample rate chosen so the expected
  // values are exact.
  // -------------------------------------------------------------------------
  group('highPassFilter (examples/common.cpp)', () {
    // The original filters *in place* and reads `data[i-1]` after it has
    // already been overwritten with the previous output, so for i ≥ 1 the
    // recurrence collapses to y[i] = alpha·(y[i-1] + x[i] - y[i-1]) =
    // alpha·x[i]: a constant gain, not a high-pass. The port reproduces that
    // exactly (vad_simple compares energy *ratios*, so the gain cancels and
    // the decisions are unaffected either way).
    test('matches the original in-place recurrence step by step', () {
      // cutoff 100 Hz, 16 kHz: rc = 1/(2π·100), dt = 1/16000,
      // alpha = dt/(rc+dt) = 0.0377…
      final data = Float32List.fromList([1.0, 1.0, 0.5, -0.25]);
      final rc = 1.0 / (2.0 * math.pi * 100.0);
      final dt = 1.0 / 16000.0;
      final alpha = dt / (rc + dt);
      highPassFilter(data, 100.0, 16000.0);
      expect(data[0], 1.0); // y0 = x0
      expect(data[1], closeTo(alpha, 1e-7)); // a·(1 + 1 - 1)
      expect(data[2], closeTo(alpha * 0.5, 1e-7)); // a·(y1 + 0.5 - y1)
      expect(data[3], closeTo(alpha * -0.25, 1e-7));
    });
    test('scales a tone by alpha after the first sample', () {
      final n = 16000;
      final rc = 1.0 / (2.0 * math.pi * 100.0);
      final dt = 1.0 / 16000.0;
      final alpha = dt / (rc + dt);
      final tone = Float32List(n);
      for (var i = 0; i < n; i++) {
        tone[i] = 0.5 * math.sin(2 * math.pi * 1000 * i / 16000);
      }
      final raw = Float32List.fromList(tone);
      highPassFilter(tone, 100.0, 16000.0);
      for (var i = 1; i < n; i += 997) {
        expect(tone[i], closeTo(alpha * raw[i], 1e-6));
      }
    });
    test('empty input is a no-op', () {
      expect(() => highPassFilter(Float32List(0), 100.0, 16000.0),
          returnsNormally);
    });
  });

  group('vadSimple (examples/common.cpp)', () {
    // 1 kHz sample rate, 1000 samples, last_ms 500 → n_samples_last 500,
    // freq_thold 0 → no filter; energies are plain means of |x|.
    Float32List twoLevels(double first, double last) {
      final out = Float32List(1000);
      for (var i = 0; i < 1000; i++) {
        final a = i < 500 ? first : last;
        out[i] = i.isEven ? a : -a;
      }
      return out;
    }

    bool vad(Float32List pcm) => vadSimple(pcm,
        sampleRate: 1000, lastMs: 500, vadThold: 0.6, freqThold: 0.0);

    test('quiet tail after speech → true (speech ended)', () {
      // energy_all 0.3, energy_last 0.1; 0.1 > 0.6·0.3 = 0.18 is false → true
      expect(vad(twoLevels(0.5, 0.1)), isTrue);
      // energy_all 0.35, energy_last 0.2; 0.2 > 0.21 is false → true
      expect(vad(twoLevels(0.5, 0.2)), isTrue);
    });
    test('tail still loud → false', () {
      // energy_all 0.4, energy_last 0.3; 0.3 > 0.24 → false
      expect(vad(twoLevels(0.5, 0.3)), isFalse);
      // speech starting in the tail
      expect(vad(twoLevels(0.1, 0.5)), isFalse);
    });
    test('flat buffers follow the original arithmetic exactly', () {
      // all zero: energy_last 0 > 0 is false → true (original does the same)
      expect(vad(twoLevels(0.0, 0.0)), isTrue);
      // all loud: 0.5 > 0.6·0.5 = 0.3 → false
      expect(vad(twoLevels(0.5, 0.5)), isFalse);
    });
    test('too short for last_ms → false ("assume no speech")', () {
      expect(
          vadSimple(Float32List(400), sampleRate: 1000, lastMs: 500), isFalse);
      expect(
          vadSimple(Float32List(500), sampleRate: 1000, lastMs: 500), isFalse);
    });
    test('does not modify its input', () {
      final pcm = twoLevels(0.5, 0.1);
      final copy = Float32List.fromList(pcm);
      vadSimple(pcm, sampleRate: 1000, lastMs: 500, freqThold: 100.0);
      expect(pcm, copy);
    });
    test('16 kHz, defaults: 1 s of tone then 1 s of near-silence is a cut', () {
      final pcm = Float32List(32000);
      final rnd = math.Random(7);
      for (var i = 0; i < 32000; i++) {
        pcm[i] = i < 16000
            ? 0.3 * math.sin(2 * math.pi * 440 * i / 16000)
            : (rnd.nextDouble() - 0.5) * 0.002; // room tone
      }
      expect(vadSimple(pcm, sampleRate: 16000), isTrue);
      // Same tone throughout: still speaking.
      for (var i = 16000; i < 32000; i++) {
        pcm[i] = 0.3 * math.sin(2 * math.pi * 440 * i / 16000);
      }
      expect(vadSimple(pcm, sampleRate: 16000), isFalse);
    });
  });

  group('pcm16ToFloat', () {
    test('scales by 1/32768 like whisper.cpp readers', () {
      final bytes = Uint8List(8);
      final bd = ByteData.sublistView(bytes);
      bd.setInt16(0, 0, Endian.little);
      bd.setInt16(2, 32767, Endian.little);
      bd.setInt16(4, -32768, Endian.little);
      bd.setInt16(6, 16384, Endian.little);
      final f = pcm16ToFloat(bytes);
      expect(f, [0.0, 32767 / 32768, -1.0, 0.5]);
    });
    test('ignores an odd trailing byte', () {
      expect(pcm16ToFloat(Uint8List.fromList([0, 0, 7])).length, 1);
    });
  });

  // Synthetic recording: 440 Hz tone (speech) everywhere except the given
  // silent spans, at 16 kHz.
  Float32List synth(int seconds, List<(double, double)> silences) {
    const sr = 16000;
    final n = seconds * sr;
    final out = Float32List(n);
    final rnd = math.Random(3);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final silent = silences.any((s) => t >= s.$1 && t < s.$2);
      out[i] = silent
          ? (rnd.nextDouble() - 0.5) * 0.002
          : 0.3 * math.sin(2 * math.pi * 440 * t);
    }
    return out;
  }

  group('findSilentCut', () {
    const sr = 16000;
    test('lands in the pause nearest the nominal cut', () {
      // Nominal 57.5 s; pause 59.0–60.5 s. Walking outward, the first 1 s
      // tail that vad_simple calls quiet ends ~0.6 s into the pause (the
      // original fires as soon as the tail energy drops under 0.6× the
      // buffer mean), so the cut — the tail's middle — sits just inside
      // the pause, shortly after the speech stopped.
      final audio = synth(70, [(59.0, 60.5)]);
      final cut = findSilentCut(
        audio: audio,
        audioStartFrame: 0,
        nominalFrame: (57.5 * sr).round(),
        sampleRate: sr,
      );
      expect(cut, isNotNull);
      expect(cut! / sr, inInclusiveRange(59.0, 59.6));
    });
    test('prefers the closer of two pauses', () {
      // Nominal 56 s between pauses 54–55.5 and 59–60.5: the earlier one
      // is nearer; approached from its far side the cut lands near its end.
      final audio = synth(70, [(54.0, 55.5), (59.0, 60.5)]);
      final cut = findSilentCut(
        audio: audio,
        audioStartFrame: 0,
        nominalFrame: (56.0 * sr).round(),
        sampleRate: sr,
      )!;
      expect(cut / sr, inInclusiveRange(54.0, 55.5));
    });
    test('returns null when nobody stops talking', () {
      final audio = synth(70, const []);
      expect(
        findSilentCut(
          audio: audio,
          audioStartFrame: 0,
          nominalFrame: 57 * sr,
          sampleRate: sr,
        ),
        isNull,
      );
    });
    test('respects the audio window it was given', () {
      // Window covers 50–62 s only; a pause at 63 s is out of reach.
      final full = synth(70, [(63.0, 64.5)]);
      final window = Float32List.sublistView(full, 50 * sr, 62 * sr);
      expect(
        findSilentCut(
          audio: window,
          audioStartFrame: 50 * sr,
          nominalFrame: (57.5 * sr).round(),
          sampleRate: sr,
        ),
        isNull,
      );
    });
  });

  group('snapChunksToSilence', () {
    const sr = 16000;

    test('re-centres the seam on the pause and keeps the overlap', () async {
      // 150 s: chunks 0–60 / 55–115 / 110–150, seams at 57.5 and 112.5.
      // Pauses at 59–60.5 (cut → 59.5) and 111–112.5 (cut → 111.5).
      final audio = synth(150, [(59.0, 60.5), (111.0, 112.5)]);
      final plans = planChunks(totalFrames: audio.length, sampleRate: sr);
      final snapped = await snapChunksToSilence(
        plans,
        sampleRate: sr,
        totalFrames: audio.length,
        read: (a, b) async => Float32List.sublistView(audio, a, b),
      );
      expect(snapped.length, 3);
      expect(snapped[0].startFrame, 0);
      expect(snapped[2].endFrame, audio.length);
      expect(snapped.map((p) => p.index), [0, 1, 2]);
      // Each seam (middle of the overlap) now lies inside its pause, the
      // 5 s overlap is preserved, and the chunks stay ~60 s.
      final seam1 = (snapped[1].startFrame + snapped[0].endFrame) / 2 / sr;
      final seam2 = (snapped[2].startFrame + snapped[1].endFrame) / 2 / sr;
      expect(seam1, inInclusiveRange(59.0, 60.5));
      expect(seam2, inInclusiveRange(111.0, 112.5));
      expect(snapped[0].endFrame - snapped[1].startFrame, 5 * sr);
      expect(snapped[1].endFrame - snapped[2].startFrame, 5 * sr);
      expect(snapped[0].endFrame / sr, closeTo(62, 1));
      expect(snapped[1].startFrame / sr, closeTo(57, 1));
      expect(snapped[1].endFrame / sr, closeTo(114, 1));
      expect(snapped[2].startFrame / sr, closeTo(109, 1));
    });

    test('leaves plans alone without a pause or with one chunk', () async {
      final audio = synth(150, const []);
      final plans = planChunks(totalFrames: audio.length, sampleRate: sr);
      final snapped = await snapChunksToSilence(
        plans,
        sampleRate: sr,
        totalFrames: audio.length,
        read: (a, b) async => Float32List.sublistView(audio, a, b),
      );
      for (var i = 0; i < plans.length; i++) {
        expect(snapped[i].startFrame, plans[i].startFrame);
        expect(snapped[i].endFrame, plans[i].endFrame);
      }
      final one = planChunks(totalFrames: 30 * sr, sampleRate: sr);
      expect(
        await snapChunksToSilence(one,
            sampleRate: sr,
            totalFrames: 30 * sr,
            read: (a, b) async => throw StateError('must not read')),
        same(one),
      );
    });
  });

  group('contextPromptFor (stream --keep-context)', () {
    TimedSegment seg(double from, double to, String text) => TimedSegment(
          start: Duration(milliseconds: (from * 1000).round()),
          end: Duration(milliseconds: (to * 1000).round()),
          text: text,
        );

    test('uses only segments that end before the next chunk starts', () {
      final prev = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [
          seg(0, 20, 'We met on Monday.'),
          seg(20, 54, 'The budget was approved.'),
          seg(54, 58, 'Then we talked about'), // reaches into the overlap
        ],
      );
      expect(contextPromptFor(prev, const Duration(seconds: 55)),
          'We met on Monday. The budget was approved.');
    });

    test('CJK joins without spaces and caps by characters', () {
      final prev = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [
          seg(0, 10, '一' * 80),
          seg(10, 20, '二' * 30),
          seg(20, 30, '三' * 30),
        ],
      );
      final out = contextPromptFor(prev, const Duration(seconds: 55));
      expect(out, '${'二' * 30}${'三' * 30}');
      expect(out.length, lessThanOrEqualTo(maxContextCharsCjk));
    });

    test('a single over-long segment keeps its tail', () {
      final prev = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [seg(0, 30, '好' * 150)],
      );
      final out = contextPromptFor(prev, const Duration(seconds: 55));
      expect(out.length, maxContextCharsCjk);
    });

    test('skips artifacts and special tokens, empty when nothing precedes', () {
      final prev = ChunkTranscript(
        offset: Duration.zero,
        length: const Duration(seconds: 60),
        text: '',
        segments: [seg(0, 3, '[BLANK_AUDIO]'), seg(56, 58, 'late words')],
      );
      expect(contextPromptFor(prev, const Duration(seconds: 55)), '');
      final untimed = const ChunkTranscript(
        offset: Duration.zero,
        length: Duration(seconds: 60),
        text: '[_BEG_]plain tail',
      );
      expect(contextPromptFor(untimed, const Duration(seconds: 55)),
          'plain tail');
    });
  });

  group('buildInitialPrompt', () {
    test('null when nothing to say, else script prompt then context', () {
      expect(buildInitialPrompt(null, ''), isNull);
      expect(buildInitialPrompt('  ', ''), isNull);
      expect(buildInitialPrompt(null, 'we said this'), 'we said this');
      expect(buildInitialPrompt('以下是普通话的句子。', ''), '以下是普通话的句子。');
      expect(buildInitialPrompt('以下是普通话的句子。', '买牛奶。'), '以下是普通话的句子。买牛奶。');
      expect(buildInitialPrompt('Notes.', 'we said this'), 'Notes. we said this');
    });
  });

  group('whisperRequestLanguage (plugin rejects auto)', () {
    test('known tags pass through, unknown fall back to the UI language', () {
      expect(whisperRequestLanguage('zh-CN', fallback: 'en'), 'zh');
      expect(whisperRequestLanguage('xx-YY', fallback: 'zh'), 'zh');
      expect(whisperRequestLanguage('', fallback: 'en'), 'en');
      expect(whisperRequestLanguage('auto', fallback: 'zh'), 'zh');
      // A fallback whisper does not know either ends at English.
      expect(whisperRequestLanguage('auto', fallback: 'xx'), 'en');
    });
    test('never yields auto', () {
      for (final tag in ['auto', '', 'zz', 'zh-CN', 'ja-JP']) {
        expect(whisperRequestLanguage(tag, fallback: 'en'),
            isNot(whisperAutoLanguage));
      }
    });
  });
}
