/// Free-tier daily allowance: [limit] photos per local calendar day. Pure
/// logic (no clock of its own) so it is unit-testable; the store persists it.
class DailyQuota {
  DailyQuota({required this.limit, int used = 0, String day = ''}) {
    _used = used;
    _day = day;
  }

  final int limit;
  int _used = 0;
  String _day = '';

  int get usedRaw => _used;
  String get dayRaw => _day;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Resets the counter when [now] is on a different local day than the
  /// last recorded use. Called by every accessor so a store loaded yesterday
  /// never shows yesterday's count.
  void _roll(DateTime now) {
    final k = dayKey(now);
    if (k != _day) {
      _day = k;
      _used = 0;
    }
  }

  int used(DateTime now) {
    _roll(now);
    return _used;
  }

  int remaining(DateTime now) {
    _roll(now);
    final r = limit - _used;
    return r < 0 ? 0 : r;
  }

  bool canUse(DateTime now) => remaining(now) > 0;

  /// Records one use. Returns false (and records nothing) when exhausted.
  bool consume(DateTime now) {
    _roll(now);
    if (_used >= limit) return false;
    _used += 1;
    return true;
  }

  Map<String, dynamic> toJson() => {'used': _used, 'day': _day};

  static DailyQuota fromJson(Map<String, dynamic>? j, {required int limit}) {
    if (j == null) return DailyQuota(limit: limit);
    final used = j['used'];
    final day = j['day'];
    return DailyQuota(
      limit: limit,
      used: used is num ? used.toInt() : 0,
      day: day is String ? day : '',
    );
  }
}
