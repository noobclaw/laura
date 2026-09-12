import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'audio_chunks.dart';
import 'whisper_language.dart';

/// Why whisper.cpp next to the system recognizer (2026-09-05):
///
/// The system engine is the better product where it works — live text, no
/// audio written — but "where it works" turned out to be the problem on
/// iPhones: it rides on Siri/dictation switches and per-language assets the
/// user never installed, and it stops mid-sentence when the OS feels like it
/// ("系统语音识别中断了", "只支持英文"). A bundled whisper.cpp model depends on
/// nothing outside the app bundle: ~100 languages, works on every device the
/// app installs on, and — because the weights ship inside the package —
/// still no INTERNET permission and no download, ever.
///
/// Trade-offs, all deliberate: text arrives after the recording stops (M1),
/// the recording exists as a temp WAV until it is transcribed, and the app
/// grows by the model (~57 MB). `ggml-base-q5_1` is the smallest multilingual
/// model whose Chinese is usable; [modelAsset] is the one place to swap in
/// `small` later.

/// How a transcription attempt failed — each maps to a specific message.
enum WhisperFailure {
  /// The bundled model could not be copied or loaded (damaged install).
  modelUnavailable,

  /// The recording is shorter than a spoken word.
  audioTooShort,

  /// The recorder produced something that is not a readable WAV.
  audioUnreadable,

  /// whisper.cpp returned an error for a chunk.
  transcriptionFailed,
}

class WhisperEngineException implements Exception {
  WhisperEngineException(this.kind, {this.detail, this.partialText = ''});

  final WhisperFailure kind;

  /// Native error text, for the "(detail)" line under the message.
  final String? detail;

  /// Whatever was transcribed before the failure — never thrown away.
  final String partialText;

  @override
  String toString() => 'WhisperEngineException(${kind.name}, $detail)';
}

/// Result of [WhisperEngine.transcribeWav].
class WhisperTranscript {
  const WhisperTranscript({
    required this.text,
    required this.completed,
    required this.chunkCount,
  });

  final String text;

  /// False when the caller cancelled between chunks; [text] then covers
  /// only the chunks that finished.
  final bool completed;
  final int chunkCount;
}

/// Bundled-model whisper.cpp transcription of a WAV file.
class WhisperEngine {
  WhisperEngine();

  /// The one place that decides which model ships. `base-q5_1` = multilingual
  /// base weights, 5-bit quantised: ~57 MB, ~1× realtime on a 2020 phone.
  /// Swap for `ggml-small-q5_1.bin` (~190 MB) if accuracy wins over size.
  static const String modelAsset = 'assets/models/ggml-base-q5_1.bin';
  static const String modelFileName = 'ggml-base-q5_1.bin';
  static const String modelDisplayName = 'Whisper base';
  static const int modelSizeMb = 57;

  /// Recordings shorter than this hold no word worth a note.
  static const Duration minAudio = Duration(milliseconds: 700);

  Future<String>? _modelReady;

  /// Copies the model out of the asset bundle into the app-support directory
  /// once (whisper.cpp reads a file path; Flutter assets are not files on
  /// Android). Idempotent and memoised; the copy is verified by length via a
  /// sidecar marker so later launches never load the 57 MB asset again.
  Future<String> ensureModel() => _modelReady ??= _ensureModel().catchError(
        (Object e) {
          // Let the next call retry instead of caching the failure.
          _modelReady = null;
          throw e;
        },
      );

  Future<String> _ensureModel() async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/whisper');
    final file = File('${dir.path}/$modelFileName');
    final marker = File('${file.path}.ok');
    try {
      if (await file.exists() && await marker.exists()) {
        final expected = int.tryParse((await marker.readAsString()).trim());
        if (expected != null && expected == await file.length()) {
          return file.path;
        }
      }
    } catch (e) {
      debugPrint('whisper model marker check failed: $e');
    }

    final ByteData data;
    try {
      data = await rootBundle.load(modelAsset);
    } catch (e) {
      throw WhisperEngineException(WhisperFailure.modelUnavailable,
          detail: 'asset missing: $e');
    }
    try {
      await dir.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename(file.path);
      await marker.writeAsString('${data.lengthInBytes}', flush: true);
    } catch (e) {
      throw WhisperEngineException(WhisperFailure.modelUnavailable,
          detail: 'copy failed: $e');
    }
    return file.path;
  }

  /// Forgets the copied model so the next [ensureModel] re-copies it. Called
  /// when whisper.cpp refuses to load the file (partial copy, damaged flash).
  Future<void> _discardModel(String path) async {
    _modelReady = null;
    try {
      await File('$path.ok').delete();
    } catch (_) {}
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Whether the text decoded from one chunk primes the next one — the
  /// counterpart of `examples/stream --keep-context`, see
  /// [contextPromptFor]. Off, every chunk starts cold (whisper.cpp's own
  /// `no_context` default) and a sentence cut by a chunk edge loses its
  /// first words' context.
  static const bool carryContextBetweenChunks = true;

  /// Transcribes [wavPath]. [languageTag] is the app's dictation tag
  /// ("zh-CN", "en-US"); it is mapped to whisper's codes here. A tag whisper
  /// does not know would mean `auto`, which the plugin rejects, so it falls
  /// back to [fallbackLanguageTag] (see [whisperRequestLanguage]).
  ///
  /// Long recordings are cut into overlapping chunks (see audio_chunks.dart)
  /// whose seams are moved onto pauses by the energy VAD ported from
  /// whisper.cpp's examples; [onProgress] reports 0..1 across all chunks and
  /// [isCancelled] is polled between chunks — a chunk already running
  /// finishes (whisper.cpp has no cancel), the rest is skipped and the
  /// result says `completed: false`.
  ///
  /// Temporary chunk files live in the system temp directory and are deleted
  /// before this returns, success or failure. The caller owns [wavPath].
  Future<WhisperTranscript> transcribeWav(
    String wavPath, {
    required String languageTag,
    String fallbackLanguageTag = 'en',
    void Function(double progress, int chunk, int chunkCount)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final source = File(wavPath);
    final WavInfo info;
    try {
      final length = await source.length();
      final raf = await source.open();
      try {
        final head = await raf.read(math.min(length, 64 * 1024));
        info = parseWavHeader(head, fileLength: length);
      } finally {
        await raf.close();
      }
    } on FormatException catch (e) {
      throw WhisperEngineException(WhisperFailure.audioUnreadable,
          detail: e.message);
    } catch (e) {
      throw WhisperEngineException(WhisperFailure.audioUnreadable,
          detail: '$e');
    }
    if (info.duration < minAudio) {
      throw WhisperEngineException(WhisperFailure.audioTooShort);
    }

    final modelPath = await ensureModel();
    final language =
        whisperRequestLanguage(languageTag, fallback: fallbackLanguageTag);
    final scriptPrompt = whisperInitialPrompt(languageTag);

    // Only the native layout can be sliced byte-exactly; anything else goes
    // through as one piece and the plugin's converter normalises it.
    var plans = info.isWhisperNative
        ? planChunks(totalFrames: info.frameCount, sampleRate: info.sampleRate)
        : [ChunkPlan(index: 0, startFrame: 0, endFrame: info.frameCount)];
    final slice = info.isWhisperNative && plans.length > 1;
    if (slice) {
      // Move each seam onto a pause (energy VAD, whisper.cpp examples'
      // vad_simple) so no word sits on the merge line. Only the few seconds
      // around each seam are read; the recording is never held in memory.
      try {
        plans = await snapChunksToSilence(
          plans,
          sampleRate: info.sampleRate,
          totalFrames: info.frameCount,
          read: (start, end) => _readFloat(source, info, start, end),
        );
      } catch (e) {
        // A read hiccup only costs the nicer cut points, not the transcript.
        debugPrint('whisper seam snapping skipped: $e');
      }
    }

    final tmpRoot = await getTemporaryDirectory();
    final work = Directory(
        '${tmpRoot.path}/echojot_whisper_${DateTime.now().microsecondsSinceEpoch}');
    await work.create(recursive: true);

    final results = <ChunkTranscript>[];
    var completed = true;
    try {
      for (final plan in plans) {
        if (isCancelled?.call() == true) {
          completed = false;
          break;
        }
        final chunkPath = slice
            ? await _writeChunk(source, info, plan, work)
            : wavPath;
        final context = carryContextBetweenChunks && results.isNotEmpty
            ? contextPromptFor(
                results.last, _frames(plan.startFrame, info.sampleRate))
            : '';
        final response = await _transcribeFile(
          chunkPath,
          modelPath: modelPath,
          language: language,
          prompt: buildInitialPrompt(scriptPrompt, context),
          onProgress: onProgress == null
              ? null
              : (pct) => onProgress(
                    (plan.index + pct / 100) / plans.length,
                    plan.index + 1,
                    plans.length,
                  ),
          partialSoFar: () => mergeChunkTranscripts(results),
        );
        results.add(ChunkTranscript(
          offset: _frames(plan.startFrame, info.sampleRate),
          length: _frames(plan.frameCount, info.sampleRate),
          text: response.text,
          segments: response.segments
              ?.map((s) => TimedSegment(
                    start: s.fromTs,
                    end: s.toTs,
                    text: s.text,
                  ))
              .toList(growable: false),
        ));
        onProgress?.call((plan.index + 1) / plans.length, plan.index + 1,
            plans.length);
      }
    } finally {
      // The plugin converts every input to "<input>.wav" beside it; sweep
      // both the chunks and that sibling of the original.
      try {
        await work.delete(recursive: true);
      } catch (_) {}
      try {
        final converted = File('$wavPath.wav');
        if (await converted.exists()) await converted.delete();
      } catch (_) {}
    }

    return WhisperTranscript(
      text: mergeChunkTranscripts(results),
      completed: completed,
      chunkCount: results.length,
    );
  }

  /// Frees the model parked in native memory (it is kept loaded between
  /// sessions so push-to-talk does not pay the multi-second load twice).
  Future<void> release() async {
    try {
      await const Whisper(model: WhisperModel.base).releaseModel();
    } catch (e) {
      debugPrint('whisper release skipped: $e');
    }
  }

  Future<WhisperTranscribeResponse> _transcribeFile(
    String path, {
    required String modelPath,
    required String language,
    required String? prompt,
    required void Function(int percent)? onProgress,
    required String Function() partialSoFar,
  }) async {
    try {
      // Everything not set here is whisper.cpp's `whisper_full_default_params
      // (WHISPER_SAMPLING_GREEDY)` as examples/cli uses it: greedy best_of 5,
      // temperature 0.0 with +0.2 fallback steps, entropy_thold 2.4,
      // logprob_thold -1.0, no_speech_thold 0.6, suppress_blank on,
      // max_len 0, token_timestamps off, print_special off, translate off.
      // The plugin exposes none of those, which is fine: they are the values
      // we would set. See REFERENCE.md for the full ledger.
      return await const Whisper(model: WhisperModel.base).transcribe(
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: language,
          // whisper.cpp's own default; more threads than cores only thrash.
          threads: math.max(1, math.min(4, Platform.numberOfProcessors)),
          // Timestamped segments are what the chunk merge assigns by.
          isNoTimestamps: false,
          // Script steering (zh) + the previous chunk's tail; whisper.cpp
          // tokenises it into `prompt_tokens`, exactly what examples/stream
          // passes between windows with --keep-context.
          initialPrompt: prompt,
          // `no_context = false`: within one chunk the 30 s decode windows
          // condition on what was just decoded (examples/stream
          // --keep-context; OpenAI's condition_on_previous_text=True).
          // whisper.cpp's default is `true`; the plugin's is `false`, and it
          // is set explicitly so a plugin default change cannot flip it.
          noContext: false,
          // Deliberate deviation from whisper.cpp's default (false): this is
          // dictation, and the tail of every recording is the silence after
          // the user stops talking — exactly what breeds "[BLANK_AUDIO]",
          // "(music)" and "♪". Costs literal brackets in dictated text.
          suppressNonSpeechTokens: true,
          keepModelLoaded: true,
        ),
        modelPath: modelPath,
        onProgress: onProgress,
      );
    } catch (e) {
      final msg = '$e';
      final lower = msg.toLowerCase();
      if (lower.contains('model') ||
          lower.contains('initialize') ||
          lower.contains('init')) {
        await _discardModel(modelPath);
        throw WhisperEngineException(WhisperFailure.modelUnavailable,
            detail: msg, partialText: partialSoFar());
      }
      throw WhisperEngineException(WhisperFailure.transcriptionFailed,
          detail: msg, partialText: partialSoFar());
    }
  }

  static Duration _frames(int frames, int sampleRate) =>
      Duration(microseconds: frames * 1000000 ~/ sampleRate);

  /// Reads frames [start, end) of the (16 kHz mono PCM16) recording as float
  /// samples, the way whisper.cpp's readers scale them.
  static Future<Float32List> _readFloat(
      File source, WavInfo info, int start, int end) async {
    final raf = await source.open();
    try {
      await raf.setPosition(info.dataOffset + start * info.bytesPerFrame);
      final bytes = await raf.read((end - start) * info.bytesPerFrame);
      return pcm16ToFloat(bytes);
    } finally {
      await raf.close();
    }
  }

  /// Writes one chunk as a standalone 16 kHz mono PCM16 WAV.
  static Future<String> _writeChunk(
      File source, WavInfo info, ChunkPlan plan, Directory work) async {
    final bytesPerFrame = info.bytesPerFrame;
    final start = info.dataOffset + plan.startFrame * bytesPerFrame;
    final length = plan.frameCount * bytesPerFrame;
    final out = File('${work.path}/chunk_${plan.index}.wav');
    final raf = await source.open();
    try {
      await raf.setPosition(start);
      final payload = await raf.read(length);
      final sink = out.openWrite();
      sink.add(wavHeader(
        sampleRate: info.sampleRate,
        channels: info.channels,
        bitsPerSample: info.bitsPerSample,
        dataLength: payload.length,
      ));
      sink.add(payload);
      await sink.close();
    } finally {
      await raf.close();
    }
    return out.path;
  }
}
