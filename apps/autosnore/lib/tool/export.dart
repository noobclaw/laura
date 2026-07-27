import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'ui_common.dart';

/// Build a CSV of one night's events and hand it to the system share sheet.
/// Written to the cache dir (not the sandbox) since it is a transient export;
/// no network is involved — the OS share sheet routes it wherever the user picks.
/// Returns false if the export could not be produced or shared.
Future<bool> shareSessionCsv(SleepSession s) async {
  try {
    final buf = StringBuffer()
      ..writeln('index,start_time,duration_ms,peak_dbfs,avg_dbfs');
    for (int i = 0; i < s.events.length; i++) {
      final e = s.events[i];
      buf.writeln('${i + 1},${formatClock(e.startMs)},${e.durationMs},'
          '${e.peakDb.toStringAsFixed(1)},${e.avgDb.toStringAsFixed(1)}');
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${s.id}.csv');
    await f.writeAsString(buf.toString(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      text: 'AutoSnore ${formatShortDate(s.startMs)}',
    ));
    return true;
  } catch (e) {
    debugPrint('shareSessionCsv failed: $e');
    return false;
  }
}
