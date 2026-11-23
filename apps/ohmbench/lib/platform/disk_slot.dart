import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// What went wrong with a [DiskSlot], for the banner the UI shows.
enum DiskProblem { unreadable, cannotLoad, cannotSave }

/// One JSON document in the app's private support folder.
///
/// OhmBench keeps three of these: the circuits, the Pro flag and the
/// preferences. The rules are the ones a user's only copy of a circuit
/// needs:
///
/// * A save goes to `<name>.part` first and is renamed into place, so the
///   file on disk is always either the previous document or the new one.
/// * Saves never overlap. While one is on its way to disk, newer documents
///   replace each other in a single waiting slot; only the newest is written
///   next.
/// * A file that exists but does not decode is moved to
///   `<name>.damaged-<epoch ms>` before anything else happens, and reported.
///   If it cannot be moved, the slot freezes: [put] is ignored for the rest
///   of the session so the damaged bytes are never overwritten.
class DiskSlot {
  DiskSlot(this.name, {this.onProblem, this.onSaved});

  final String name;
  final void Function(DiskProblem problem, String detail)? onProblem;
  final VoidCallback? onSaved;

  static Future<Directory>? _folder;

  /// The folder every slot lives in, created on first use.
  static Future<Directory> _root() => _folder ??= () async {
        final base = await getApplicationSupportDirectory();
        final dir = Directory('${base.path}${Platform.pathSeparator}bench');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }();

  bool _frozen = false;

  /// True after a load that may have left real data unread. Saving stays
  /// off until the next launch.
  bool get frozen => _frozen;

  String? _waiting;
  Future<void>? _writer;

  Future<File> _target() async =>
      File('${(await _root()).path}${Platform.pathSeparator}$name');

  /// The stored document, or null when there is none (first launch, tests
  /// without a platform folder, or a damaged file that was set aside).
  Future<Map<String, dynamic>?> load() async {
    final File file;
    final String text;
    try {
      file = await _target();
      if (!await file.exists()) return null;
      text = await file.readAsString();
    } catch (e) {
      _frozen = true;
      _report(DiskProblem.cannotLoad, '$e');
      return null;
    }
    final decoded = _decode(text);
    if (decoded != null) return decoded;
    final aside =
        '${file.path}.damaged-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await file.rename(aside);
      _report(DiskProblem.unreadable, aside);
    } catch (_) {
      _frozen = true;
      _report(DiskProblem.unreadable, file.path);
    }
    return null;
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// Schedules [document] to be written. The JSON is captured now, so later
  /// changes to the caller's objects do not leak into this save.
  void put(Map<String, dynamic> document) {
    if (_frozen) return;
    _waiting = jsonEncode(document);
    _writer ??= _drain();
  }

  /// Resolves once everything handed to [put] so far is on disk.
  Future<void> settle() async {
    while (_writer != null) {
      await _writer;
    }
  }

  Future<void> _drain() async {
    try {
      while (_waiting != null) {
        final text = _waiting!;
        _waiting = null;
        await _commit(text);
      }
    } finally {
      _writer = null;
    }
  }

  Future<void> _commit(String text) async {
    try {
      final file = await _target();
      final part = File('${file.path}.part');
      final sink = part.openWrite();
      sink.write(text);
      await sink.flush();
      await sink.close();
      await part.rename(file.path);
      onSaved?.call();
    } catch (e) {
      _report(DiskProblem.cannotSave, '$e');
    }
  }

  void _report(DiskProblem problem, String detail) {
    debugPrint('disk $name ${problem.name}: $detail');
    onProblem?.call(problem, detail);
  }
}
