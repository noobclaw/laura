import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The one JSON document every factory app keeps, persisted the way a user's
/// only copy of their data deserves:
///
/// - **Atomic**: written to a sibling temp file, flushed, then renamed over
///   the real one. A crash mid-write leaves the old file or the new one,
///   never half a document.
/// - **Serialised**: writes queue behind each other, so a burst of edits
///   cannot interleave two writers on one path.
/// - **Never destructive on read failure**: a file that exists but will not
///   parse is renamed aside (`<name>.corrupt-<ms>`), not overwritten by the
///   next save. The 2026-09-02 audit found four apps that would silently
///   replace a damaged file — i.e. all of a user's data — with an empty
///   store on the next edit.
///
/// Usage: `read()` once at startup (null means "start empty"), then
/// `write(json)` after every mutation. Stores must refuse to `write` before
/// their `read` has completed; see `RemcardStore` for the pattern.
class JsonFileStore {
  JsonFileStore(this.fileName, {this.onTrouble});

  /// File name inside the app's documents directory, e.g. `remcard.json`.
  final String fileName;

  /// Called (with an English tag and the platform's own message) whenever a
  /// write fails or a document has to be quarantined.
  ///
  /// Draftbook-local addition to the shell's copy: this app's whole promise is
  /// "nothing you wrote is ever lost", so a failed save that only reaches
  /// `debugPrint` is the one failure it must never have. The app turns this
  /// into a banner; see `DraftbookStore.storageTrouble`.
  final void Function(String kind, String detail)? onTrouble;

  Future<void> _chain = Future<void>.value();

  /// The newest payload waiting to be written. A burst of edits collapses to
  /// one disk write instead of one per keystroke-debounce.
  String? _pending;

  /// True when [read] failed for a reason that leaves a real document on disk:
  /// an IO error, a missing plugin, bytes that are not valid UTF-8, or a
  /// damaged file that could not even be renamed aside.
  ///
  /// It does NOT cover the ordinary damaged-document path, because there the
  /// file has already been moved to `.corrupt-*` and writing a fresh one is
  /// correct. The caller must refuse to save while this is true: otherwise one
  /// transient read failure turns "we could not open your book" into "we
  /// replaced your book with an empty one" on the next keystroke.
  bool readFailed = false;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Loads and decodes the document. Returns null when there is nothing to
  /// load: first launch, the platform plugin being unavailable (tests), or
  /// a damaged file — which is preserved under a `.corrupt-*` name.
  Future<Map<String, dynamic>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      try {
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('$fileName unreadable, kept aside: $e');
        try {
          final kept =
              '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
          await f.rename(kept);
          onTrouble?.call('corrupt', kept);
        } catch (_) {
          // Could not move it aside, so the damaged bytes are still the only
          // copy: refuse to write over them.
          readFailed = true;
          onTrouble?.call('corrupt', f.path);
        }
        return null;
      }
    } catch (e) {
      debugPrint('$fileName load skipped: $e');
      readFailed = true;
      onTrouble?.call('load', '$e');
      return null;
    }
  }

  /// Queues an atomic write of [json]. Encoding happens synchronously so the
  /// snapshot reflects the caller's state at the moment of the call; queued
  /// writes coalesce, so a burst only ever puts the newest document on disk.
  void write(Map<String, dynamic> json) {
    _pending = jsonEncode(json);
    _chain = _chain.then((_) async {
      final payload = _pending;
      if (payload == null) return; // a later call already wrote this state
      _pending = null;
      await _writeAtomically(payload);
    });
  }

  /// Completes when every write queued so far has hit the disk.
  Future<void> flush() => _chain;

  Future<void> _writeAtomically(String payload) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('$fileName save skipped: $e');
      onTrouble?.call('save', '$e');
    }
  }
}
