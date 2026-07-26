import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/branding.dart';
import '../core/l10n.dart';
import 'models.dart';

/// Pushes the "featured" event (first in display order) to the native Android
/// home-screen widget. Everything is wrapped in try/catch: the plugin is a
/// no-op on desktop/test harnesses and must never break the app.
class WidgetBridge {
  /// Kotlin class name of the AppWidgetProvider (relative to applicationId).
  static const String _androidProvider = 'CountdownWidgetProvider';

  static Future<void> push(List<CountdownEvent> events) async {
    try {
      final sorted = sortedEvents(events, DateTime.now());
      if (sorted.isEmpty) {
        await _save('dc_title', Branding.appName);
        await _save('dc_emoji', '');
        await _save('dc_num', '—');
        await _save('dc_label', tr(zh: '还没有添加日子', en: 'No days yet'));
        await _save('dc_date', tr(zh: '打开 App 添加', en: 'Open the app to add one'));
      } else {
        final e = sorted.first;
        final s = statusOf(e, DateTime.now());
        final label = s.isToday
            ? tr(zh: '就是今天', en: 'Today!')
            : (s.isFuture
                ? tr(zh: '还有 · 天', en: 'days to go')
                : tr(zh: '已过去 · 天', en: 'days ago'));
        final num = s.isToday ? '🎉' : '${s.absDays}';
        await _save('dc_title', e.title);
        await _save('dc_emoji', e.emoji);
        await _save('dc_num', num);
        await _save('dc_label', label);
        await _save('dc_date', _formatDate(s.target));
      }
      await HomeWidget.updateWidget(androidName: _androidProvider);
    } catch (e) {
      debugPrint('widget push skipped: $e');
    }
  }

  static Future<void> _save(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  static String _formatDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
