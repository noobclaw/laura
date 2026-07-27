import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';

String two(int n) => n.toString().padLeft(2, '0');

/// "23:14" from an epoch-ms instant (local time).
String formatClock(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${two(d.hour)}:${two(d.minute)}';
}

/// "7h 12m" / "12m" / "48s" from a duration in ms.
String formatDuration(int ms) {
  final int totalSec = ms ~/ 1000;
  final int h = totalSec ~/ 3600;
  final int m = (totalSec % 3600) ~/ 60;
  final int s = totalSec % 60;
  if (h > 0) return '${h}h ${two(m)}m';
  if (m > 0) return '${m}m ${two(s)}s';
  return '${s}s';
}

/// "07/27" style short date (numeric — locale-neutral).
String formatShortDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${two(d.month)}/${two(d.day)}';
}

String bandLabel(SnoreBand b) {
  switch (b) {
    case SnoreBand.quiet:
      return tr(zh: '安静', en: 'Quiet');
    case SnoreBand.mild:
      return tr(zh: '轻微', en: 'Mild');
    case SnoreBand.moderate:
      return tr(zh: '中等', en: 'Moderate');
    case SnoreBand.loud:
      return tr(zh: '响亮', en: 'Loud');
  }
}

Color bandColor(SnoreBand b) {
  switch (b) {
    case SnoreBand.quiet:
      return const Color(0xFF43A047); // green
    case SnoreBand.mild:
      return const Color(0xFF7CB342); // light green
    case SnoreBand.moderate:
      return const Color(0xFFF9A825); // amber
    case SnoreBand.loud:
      return const Color(0xFFE53935); // red
  }
}
