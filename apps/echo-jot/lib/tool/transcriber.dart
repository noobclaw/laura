import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import 'note.dart';

/// On-device whisper transcription. The model ships inside the app bundle
/// (assets/models/ggml-base.bin, downloaded at CI build time) and is copied
/// into the app support directory on first launch — the app never touches
/// the network, which is the product's core promise.
class Transcriber {
  Transcriber(this.store);

  final NoteStore store;
  final ValueNotifier<bool> modelReady = ValueNotifier(false);
  bool _installing = false;
  bool _working = false;

  static const _assetKey = 'assets/models/ggml-base.bin';
  static const _modelFileName = 'ggml-base.bin';

  Future<String> _modelDir() async {
    final dir = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getLibraryDirectory();
    return dir.path;
  }

  /// Copy the bundled model out of assets once. ~57MB, a few seconds.
  Future<void> ensureModelInstalled() async {
    if (modelReady.value || _installing) return;
    _installing = true;
    try {
      final dir = await _modelDir();
      final target = File('$dir/$_modelFileName');
      if (!await target.exists()) {
        final data = await rootBundle.load(_assetKey);
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      modelReady.value = true;
    } finally {
      _installing = false;
    }
  }

  /// Transcribe every pending note, oldest first, one at a time.
  Future<void> drainQueue() async {
    if (_working) return;
    _working = true;
    try {
      await ensureModelInstalled();
      while (true) {
        Note? next;
        for (final n in store.notes.reversed) {
          if (n.status == NoteStatus.pending) {
            next = n;
            break;
          }
        }
        if (next == null) break;
        await _transcribeOne(next);
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _transcribeOne(Note note) async {
    note.status = NoteStatus.transcribing;
    await store.update(note);
    try {
      final whisper = Whisper(
        model: WhisperModel.base,
        modelDir: await _modelDir(),
      );
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: note.audioPath,
          language: 'auto',
          isNoTimestamps: true,
          threads: 4,
        ),
      );
      note.text = response.text.trim();
      note.status = NoteStatus.done;
    } catch (e) {
      debugPrint('transcribe failed: $e');
      note.status = NoteStatus.failed;
    }
    await store.update(note);
  }

  /// Re-queue a failed note and run again.
  Future<void> retry(Note note) async {
    note.status = NoteStatus.pending;
    await store.update(note);
    await drainQueue();
  }
}
