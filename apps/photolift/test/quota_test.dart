import 'package:flutter_test/flutter_test.dart';
import 'package:photolift/tool/eta.dart';
import 'package:photolift/tool/models.dart';
import 'package:photolift/tool/quota.dart';
import 'package:photolift/tool/store.dart';

void main() {
  group('DailyQuota', () {
    final day1 = DateTime(2026, 9, 5, 10);
    final day1Late = DateTime(2026, 9, 5, 23, 59);
    final day2 = DateTime(2026, 9, 6, 0, 1);

    test('three uses then exhausted, resets on the next day', () {
      final q = DailyQuota(limit: 3);
      expect(q.remaining(day1), 3);
      expect(q.consume(day1), isTrue);
      expect(q.consume(day1), isTrue);
      expect(q.consume(day1Late), isTrue);
      expect(q.remaining(day1Late), 0);
      expect(q.canUse(day1Late), isFalse);
      expect(q.consume(day1Late), isFalse);
      expect(q.remaining(day2), 3);
      expect(q.canUse(day2), isTrue);
    });

    test('round-trips through JSON and keeps the day', () {
      final q = DailyQuota(limit: 3);
      q.consume(day1);
      final back = DailyQuota.fromJson(q.toJson(), limit: 3);
      expect(back.used(day1), 1);
      expect(back.remaining(day1), 2);
      expect(back.remaining(day2), 3);
    });

    test('tolerates a missing or damaged record', () {
      expect(DailyQuota.fromJson(null, limit: 3).remaining(day1), 3);
      expect(DailyQuota.fromJson({'used': 'x'}, limit: 3).remaining(day1), 3);
    });
  });

  group('PhotoLiftStore gates', () {
    test('free tier: 2x only, three a day; Pro: everything', () {
      final store = PhotoLiftStore();
      final now = DateTime(2026, 9, 5, 12);
      expect(store.canStart(scale: 2, now: now), isTrue);
      expect(store.canStart(scale: 4, now: now), isFalse);
      store.consumeQuota(now);
      store.consumeQuota(now);
      store.consumeQuota(now);
      expect(store.remainingToday(now), 0);
      expect(store.canStart(scale: 2, now: now), isFalse);
      store.unlockPro();
      expect(store.pro, isTrue);
      expect(store.canStart(scale: 2, now: now), isTrue);
      expect(store.canStart(scale: 4, now: now), isTrue);
      expect(store.remainingToday(now), -1);
      // Pro never consumes quota.
      store.consumeQuota(now);
      expect(store.usedToday(now), 3);
    });
  });

  group('EtaModel', () {
    test('learns from runs and stays positive', () {
      final eta = EtaModel();
      final before = eta.estimateSeconds(4000000, EngineKind.ncnnGpu);
      eta.record(4000000, EngineKind.ncnnGpu, 20000);
      final after = eta.estimateSeconds(4000000, EngineKind.ncnnGpu);
      expect(after, greaterThan(before));
      eta.record(4000000, EngineKind.ncnnGpu, 1500);
      expect(eta.estimateSeconds(4000000, EngineKind.ncnnGpu), greaterThan(0));
      expect(eta.estimateSeconds(0, EngineKind.ncnnGpu), 0);
    });

    test('formatEta', () {
      expect(formatEta(0.4, zh: false), 'under 1 s');
      expect(formatEta(12, zh: true), '约 12 秒');
      expect(formatEta(95, zh: false), '~1m 35s');
      expect(formatEta(600, zh: true), '约 10 分钟');
    });
  });
}
