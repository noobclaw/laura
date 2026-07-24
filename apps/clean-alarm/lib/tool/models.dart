/// Pure, dependency-free alarm model + scheduling math.
///
/// Weekdays follow Dart's `DateTime.weekday`: 1 = Monday .. 7 = Sunday.
/// An empty [AlarmItem.weekdays] means a one-time alarm (rings once at the next
/// occurrence of its time, then stays put). Everything here is deterministic and
/// unit-tested; the platform notification wiring lives in `scheduler.dart`.
library;

class AlarmItem {
  AlarmItem({
    required this.id,
    required this.notifId,
    required this.hour,
    required this.minute,
    this.label = '',
    Set<int>? weekdays,
    this.enabled = true,
    this.soundOn = true,
    this.vibrate = true,
    this.snoozeMinutes = 5,
  }) : weekdays = weekdays ?? <int>{};

  final String id;

  /// Stable integer base for platform notification ids. Repeating alarms use
  /// `notifId * 10 + weekday`; one-time alarms use `notifId * 10`.
  final int notifId;

  int hour; // 0-23
  int minute; // 0-59
  String label;
  Set<int> weekdays; // subset of 1..7; empty = one-time
  bool enabled;
  bool soundOn;
  bool vibrate;
  int snoozeMinutes; // 0 = snooze off

  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool get isOneTime => weekdays.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'notifId': notifId,
        'hour': hour,
        'minute': minute,
        'label': label,
        'weekdays': weekdays.toList()..sort(),
        'enabled': enabled,
        'soundOn': soundOn,
        'vibrate': vibrate,
        'snoozeMinutes': snoozeMinutes,
      };

  factory AlarmItem.fromJson(Map<String, dynamic> j) => AlarmItem(
        id: j['id'] as String,
        notifId: (j['notifId'] as num?)?.toInt() ?? 0,
        hour: (j['hour'] as num).toInt().clamp(0, 23),
        minute: (j['minute'] as num).toInt().clamp(0, 59),
        label: (j['label'] as String?) ?? '',
        weekdays: ((j['weekdays'] as List<dynamic>?) ?? const [])
            .map((e) => (e as num).toInt())
            .where((w) => w >= 1 && w <= 7)
            .toSet(),
        enabled: (j['enabled'] as bool?) ?? true,
        soundOn: (j['soundOn'] as bool?) ?? true,
        vibrate: (j['vibrate'] as bool?) ?? true,
        snoozeMinutes: (j['snoozeMinutes'] as num?)?.toInt() ?? 5,
      );

  AlarmItem copy() => AlarmItem.fromJson(toJson());
}

const Set<int> kWeekdaysAll = {1, 2, 3, 4, 5, 6, 7};
const Set<int> kWorkdays = {1, 2, 3, 4, 5};
const Set<int> kWeekend = {6, 7};

const List<String> _weekdayShort = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayShort(int w) => _weekdayShort[(w - 1) % 7];

/// Human summary of an alarm's repeat rule, e.g. 「工作日」「周一、周三」.
String repeatLabel(Set<int> weekdays) {
  if (weekdays.isEmpty) return '仅一次';
  final s = weekdays.toSet();
  if (s.length == 7) return '每天';
  if (s.length == 5 && s.containsAll(kWorkdays)) return '工作日';
  if (s.length == 2 && s.containsAll(kWeekend)) return '周末';
  final sorted = s.toList()..sort();
  return sorted.map((w) => '周${weekdayShort(w)}').join('、');
}

/// The next moment this alarm should fire, strictly after [now], in local
/// wall-clock time. Repeating alarms scan the next 7 days for the soonest
/// selected weekday; one-time alarms fire today (if still ahead) or tomorrow.
DateTime nextTrigger(AlarmItem a, DateTime now) {
  if (a.weekdays.isEmpty) {
    final today = DateTime(now.year, now.month, now.day, a.hour, a.minute);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }
  for (var add = 0; add <= 7; add++) {
    final cand = DateTime(now.year, now.month, now.day + add, a.hour, a.minute);
    if (a.weekdays.contains(cand.weekday) && cand.isAfter(now)) return cand;
  }
  // Unreachable in practice (a full week always contains a selected weekday).
  final t = DateTime(now.year, now.month, now.day, a.hour, a.minute);
  return t.add(const Duration(days: 7));
}

/// Countdown from [now] until the alarm next rings.
Duration untilNext(AlarmItem a, DateTime now) =>
    nextTrigger(a, now).difference(now);

/// Short zh label like 「8 小时 20 分钟后响铃」for the alarm card.
String formatUntil(Duration d) {
  if (d.inMinutes < 1) return '不到 1 分钟后响铃';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days >= 1) {
    return hours > 0 ? '$days 天 $hours 小时后响铃' : '$days 天后响铃';
  }
  if (d.inHours >= 1) {
    return mins > 0 ? '${d.inHours} 小时 $mins 分钟后响铃' : '${d.inHours} 小时后响铃';
  }
  return '${d.inMinutes} 分钟后响铃';
}
