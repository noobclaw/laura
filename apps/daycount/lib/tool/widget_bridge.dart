import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/branding.dart';
import '../core/l10n.dart';
import 'models.dart';

/// Hands the featured event (first in display order) to the native Android
/// home-screen widget — as *raw data*, not as a rendered number.
///
/// The widget's day count used to be formatted here at save time and pasted
/// into the RemoteViews as a string, so it went stale at midnight and
/// "Today 🎉" celebrated for as long as the user left the app alone
/// (2026-09-02 audit R1). Now Flutter writes the target date and the
/// localized label templates; `CountdownWidgetProvider` computes the number
/// from the device clock every time it renders, and re-renders itself at
/// midnight, on time/zone changes and every 30 minutes as a backstop.
///
/// Everything is wrapped in try/catch: the plugin is a no-op on desktop/test
/// harnesses and must never break the app.
class WidgetBridge {
  /// Kotlin class name of the AppWidgetProvider (relative to applicationId).
  static const String _androidProvider = 'CountdownWidgetProvider';

  /// WidgetKit `kind` of ios/CountdownWidget/CountdownWidget.swift.
  static const String _iosKind = 'CountdownWidget';

  /// App Group shared by Runner and the widget extension on iOS — the plugin
  /// writes into this suite's UserDefaults, the extension reads from it.
  /// Must match both entitlements files.
  static const String _iosAppGroup = 'group.com.noobclaw.daycount';

  static bool _groupReady = false;

  static Future<void> _ensureGroup() async {
    if (_groupReady) return;
    if (!kIsWeb && Platform.isIOS) {
      await HomeWidget.setAppGroupId(_iosAppGroup);
    }
    _groupReady = true;
  }

  static Future<void> push(List<CountdownEvent> events) async {
    try {
      await _ensureGroup();
      final sorted = sortedEvents(events, DateTime.now());
      if (sorted.isEmpty) {
        await _save('dc_title', Branding.appName);
        await _save('dc_emoji', '');
        await _save('dc_empty_label', tr(zh: '还没有添加日子', en: 'No days yet'));
        await _save(
            'dc_empty_date', tr(zh: '打开 App 添加', en: 'Open the app to add one'));
        // Written last: a render between the keys must never see a half state.
        await _save('dc_has_event', 'false');
      } else {
        final e = sorted.first;
        await _save('dc_title', e.title);
        await _save('dc_emoji', e.emoji);
        // ISO date + repeat flag: the provider rolls yearly events forward
        // itself, so a birthday keeps counting to the *next* one after it
        // passes even if the app is never opened again.
        await _save('dc_date_iso', _iso(e.date));
        await _save('dc_yearly', e.yearlyRepeat ? 'true' : 'false');
        // Label templates in the app's language. "{n}" is replaced natively.
        await _save('dc_label_future', tr(zh: '还有 {n} 天', en: '{n} days to go'));
        await _save('dc_label_future_1', tr(zh: '还有 1 天', en: '1 day to go'));
        await _save('dc_label_past', tr(zh: '已过去 {n} 天', en: '{n} days ago'));
        await _save('dc_label_past_1', tr(zh: '已过去 1 天', en: '1 day ago'));
        await _save('dc_label_today', tr(zh: '就是今天', en: 'Today!'));
        await _save('dc_has_event', 'true');
      }
      await HomeWidget.updateWidget(
          androidName: _androidProvider, iOSName: _iosKind);
    } catch (e) {
      debugPrint('widget push skipped: $e');
    }
  }

  /// Ask the widget to re-render from the data it already has — used when
  /// the day changes while the app is open, so the phone's home screen
  /// never lags the app.
  static Future<void> refresh() async {
    try {
      await HomeWidget.updateWidget(
          androidName: _androidProvider, iOSName: _iosKind);
    } catch (e) {
      debugPrint('widget refresh skipped: $e');
    }
  }

  static Future<void> _save(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  static String _iso(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
