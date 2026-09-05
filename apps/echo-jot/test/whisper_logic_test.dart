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
  });
}
