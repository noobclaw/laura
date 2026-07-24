import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

const String _channelId = 'clean_alarm_channel';
const String _channelName = '闹钟';
const String _channelDesc = '闹钟响铃通知';
const String _toneRes = 'clean_alarm_tone'; // res/raw/clean_alarm_tone.wav

/// Notification payload format for a snooze action: `snooze|<minutes>|<label>`.
String _payload(AlarmItem a) => 'snooze|${a.snoozeMinutes}|${a.label}';

/// Background isolate entry point: handles the "贪睡" action tapped from the
/// lock screen while the app is not in the foreground. Reschedules a one-off
/// notification `minutes` from now. Must be a top-level / static function.
@pragma('vm:entry-point')
void alarmActionBackgroundHandler(NotificationResponse response) {
  if (response.actionId != 'snooze') return;
  final payload = response.payload ?? '';
  final parts = payload.split('|');
  final minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 5) : 5;
  final label = parts.length > 2 ? parts[2] : '';
  // Fire-and-forget; the isolate stays alive until this future settles.
  AlarmScheduler.scheduleSnooze(minutes, label);
}

/// Thin, heavily-guarded wrapper around flutter_local_notifications. Every
/// platform call is wrapped so unit/widget tests (which have no plugin backend)
/// silently no-op instead of throwing.
class AlarmScheduler {
  AlarmScheduler._();
  static final AlarmScheduler instance = AlarmScheduler._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // Leave the default (UTC) location; absolute fire times stay correct.
      }
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onForegroundResponse,
        onDidReceiveBackgroundNotificationResponse:
            alarmActionBackgroundHandler,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_toneRes),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
      ));
      _ready = true;
    } catch (e) {
      debugPrint('AlarmScheduler.init skipped: $e');
    }
  }

  /// Ask for the runtime permissions an alarm needs (Android 13+ notifications,
  /// Android 12+ exact alarms). Safe to call repeatedly.
  Future<void> requestPermissions() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('AlarmScheduler.requestPermissions skipped: $e');
    }
  }

  /// Cancel everything and reschedule all enabled alarms. Called on every
  /// change to the alarm list.
  Future<void> syncAll(List<AlarmItem> alarms) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      for (final a in alarms) {
        if (a.enabled) await _scheduleOne(a);
      }
    } catch (e) {
      debugPrint('AlarmScheduler.syncAll skipped: $e');
    }
  }

  Future<void> _scheduleOne(AlarmItem a) async {
    final details = NotificationDetails(android: _androidDetails(a));
    final body = a.label.isEmpty ? a.hhmm : a.label;
    if (a.isOneTime) {
      final when = _nextInstance(a.hour, a.minute, null);
      await _plugin.zonedSchedule(
        a.notifId * 10,
        _channelName,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: _payload(a),
      );
    } else {
      for (final w in a.weekdays) {
        final when = _nextInstance(a.hour, a.minute, w);
        await _plugin.zonedSchedule(
          a.notifId * 10 + w,
          _channelName,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: _payload(a),
        );
      }
    }
  }

  AndroidNotificationDetails _androidDetails(AlarmItem a) =>
      AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: a.soundOn,
        sound: a.soundOn
            ? const RawResourceAndroidNotificationSound(_toneRes)
            : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: a.vibrate,
        ongoing: true,
        autoCancel: false,
        actions: [
          if (a.snoozeMinutes > 0)
            AndroidNotificationAction(
              'snooze',
              '贪睡 ${a.snoozeMinutes} 分钟',
              cancelNotification: true,
            ),
          const AndroidNotificationAction(
            'dismiss',
            '关闭',
            cancelNotification: true,
          ),
        ],
      );

  static void _onForegroundResponse(NotificationResponse response) {
    if (response.actionId != 'snooze') return;
    final parts = (response.payload ?? '').split('|');
    final minutes = parts.length > 1 ? (int.tryParse(parts[1]) ?? 5) : 5;
    final label = parts.length > 2 ? parts[2] : '';
    scheduleSnooze(minutes, label);
  }

  /// Schedule a single one-off notification [minutes] from now. Used by both
  /// the foreground and background snooze handlers.
  static Future<void> scheduleSnooze(int minutes, String label) async {
    try {
      tzdata.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(const InitializationSettings(android: androidInit));
      final when =
          tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: const RawResourceAndroidNotificationSound(_toneRes),
        ),
      );
      await plugin.zonedSchedule(
        900000, // fixed slot for the transient snooze notification
        _channelName,
        label.isEmpty ? '贪睡结束' : label,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('AlarmScheduler.scheduleSnooze skipped: $e');
    }
  }

  tz.TZDateTime _nextInstance(int hour, int minute, int? weekday) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (weekday == null) {
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      return scheduled;
    }
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
