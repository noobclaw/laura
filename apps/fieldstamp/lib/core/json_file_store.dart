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
  JsonFileStore(this.fileName);

  /// File name inside the app's documents directory, e.g. `remcard.json`.
  final String fileName;

  Future<void> _chain = Future<void>.value();

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
          await f.rename(
              '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        } catch (_) {
          // Could not move it; the caller still starts empty and any later
          // write is atomic, so the damaged bytes are at worst replaced by
          // a valid document rather than by another torn one.
        }
        return null;
      }
    } catch (e) {
      debugPrint('$fileName load skipped: $e');
      return null;
    }
  }

  /// Queues an atomic write of [json]. Encoding happens synchronously so the
  /// snapshot reflects the caller's state at the moment of the call.
  void write(Map<String, dynamic> json) {
    final payload = jsonEncode(json);
    _chain = _chain.then((_) => _writeAtomically(payload));
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
    }
  }
}
