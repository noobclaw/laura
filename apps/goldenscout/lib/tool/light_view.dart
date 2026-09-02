import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'astro.dart';
import 'compass_rose.dart';
import 'location_store.dart';
import 'sensors.dart';

/// The almanac for one location and one date: compass rose, the day's light
/// timeline, and current sun/moon readouts. Reused by the Today tab (date =
/// today, live) and the Planner tab (any Pro-selected date).
class LightView extends StatefulWidget {
  const LightView({
    super.key,
    required this.store,
    required this.sensors,
    required this.date,
    required this.isToday,
    this.onNeedLocation,
  });

  final LocationStore store;
  final SensorHub sensors;
  final DateTime date;
  final bool isToday;
  final VoidCallback? onNeedLocation;

  @override
  State<LightView> createState() => _LightViewState();
}

class _LightViewState extends State<LightView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keep the live sun/moon marker fresh on the Today view.
    if (widget.isToday) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!store.hasActive) {
      return _NoLocation(onSet: widget.onNeedLocation);
    }
    final lat = store.activeLat!;
    final lon = store.activeLon!;
    // The device's own surroundings always show in the device zone; a saved
    // far-away site shows in its own (longitude-estimated) clock instead of
    // the meaningless "New York sunrise at 17:25 Beijing time".
    final isHere = store.activeName == 'Current location';
    final day = computeDayLight(widget.date, lat, lon, deviceZone: isHere);
    // Computed once per build, outside the sensor-driven builder below: the
    // compass fires several times a second and the moon does not move.
    final moonTimes = computeMoonTimes(widget.date, lat, lon, deviceZone: isHere);
    final now = DateTime.now();
    final refTime = widget.isToday ? now : DateTime(widget.date.year, widget.date.month, widget.date.day, 12);
    final sun = sunPosition(refTime.toUtc(), lat, lon);
    final moon = moonPosition(refTime.toUtc(), lat, lon);
    final phase = moonPhase(refTime.toUtc());

    return ListenableBuilder(
      listenable: widget.sensors,
      builder: (context, _) {
        final heading = widget.isToday ? widget.sensors.heading : null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _GoldenHero(day: day, now: widget.isToday ? now : null),
            const SizedBox(height: 16),
            _LocationHeader(store: store, day: day),
            const SizedBox(height: 12),
            CompassRose(
              sunriseAz: day.sunrise.azimuth,
              sunsetAz: day.sunset.azimuth,
              sun: sun,
              moon: moon,
              deviceHeading: heading,
            ),
            const SizedBox(height: 8),
            _RoseLegend(heading: heading),
            const SizedBox(height: 16),
            if (widget.isToday) _NowRow(sun: sun, moon: moon),
            if (widget.isToday) const SizedBox(height: 16),
            _Timeline(day: day, now: widget.isToday ? now : null),
            const SizedBox(height: 16),
            _MoonCard(phase: phase, times: moonTimes, pro: store.pro),
          ],
        );
      },
    );
  }
}

/// The hero: a dusk-sky gradient card that leads the view with the day's
/// signature golden-hour window in large tabular type, over a soft sun glyph.
/// On the live Today view it prefers the *upcoming* golden hour (morning until
/// it has passed, otherwise the evening one); on a planned date it shows the
/// evening window. Falls back gracefully on polar days.
class _GoldenHero extends StatelessWidget {
  const _GoldenHero({required this.day, required this.now});
  final DayLight day;
  final DateTime? now;

  static String _clock(DateTime? t) => t == null
      ? '--:--'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    final tab = const [FontFeature.tabularFigures()];

    // Resolve the headline: label + the two ends of the window (or a special
    // polar message).
    String label;
    String? special;
    DateTime? start;
    DateTime? end;

    if (day.polarNight) {
      label = tr(zh: '极夜', en: 'Polar night');
      special = tr(zh: '太阳整天在地平线下', en: 'The Sun stays below the horizon');
    } else if (day.polarDay) {
      label = tr(zh: '午夜太阳', en: 'Midnight sun');
      special = tr(zh: '金色的光线整日徘徊', en: 'Golden light lingers all day');
    } else {
      final amOk = day.goldenStartAm.exists && day.goldenEndAm.exists;
      final pmOk = day.goldenStartPm.exists && day.goldenEndPm.exists;
      final n = now;
      final morningUpcoming =
          amOk && n != null && day.goldenEndAm.time!.isAfter(n);
      if (morningUpcoming) {
        label = tr(zh: '清晨黄金时段', en: 'Morning golden hour');
        start = day.goldenStartAm.time;
        end = day.goldenEndAm.time;
      } else if (pmOk) {
        label = tr(zh: '傍晚黄金时段', en: 'Evening golden hour');
        start = day.goldenStartPm.time;
        end = day.goldenEndPm.time;
      } else if (amOk) {
        label = tr(zh: '清晨黄金时段', en: 'Morning golden hour');
        start = day.goldenStartAm.time;
        end = day.goldenEndAm.time;
      } else {
        label = tr(zh: '日出与日落', en: 'Sunrise & sunset');
        start = day.sunrise.time;
        end = day.sunset.time;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kDuskIndigo, kDuskRose, kGoldenAmber],
            stops: [0.0, 0.62, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Sun sinking into the corner — the emotional backdrop.
            Positioned(
              right: -30,
              bottom: -36,
              child: Icon(Icons.wb_sunny_rounded,
                  size: 188, color: white.withValues(alpha: 0.14)),
            ),
            Positioned(
              right: 26,
              top: 16,
              child: Icon(Icons.brightness_2,
                  size: 34, color: white.withValues(alpha: 0.13)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wb_twilight,
                          size: 18, color: white.withValues(alpha: 0.92)),
                      const SizedBox(width: 8),
                      Text(
                        label.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (special != null)
                    Text(
                      special,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: white,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_clock(start)} – ${_clock(end)}',
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  color: white,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: tab,
                                  letterSpacing: -0.5,
                                ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _stat(context, Icons.north_east,
                          tr(zh: '日出', en: 'Sunrise'), day.sunrise.time),
                      const SizedBox(width: 22),
                      _stat(context, Icons.south_east,
                          tr(zh: '日落', en: 'Sunset'), day.sunset.time),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String label, DateTime? t) {
    final white = Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: white.withValues(alpha: 0.85)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: white.withValues(alpha: 0.78),
                    letterSpacing: 0.3)),
            Text(
              _clock(t),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: white,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What clock a far-away site's times are in. Honest about the estimate:
/// longitude gives the zone to within an hour but knows nothing about DST.
String _zoneNote(DayLight day) {
  if (!day.zoneEstimated) {
    return tr(zh: '时间按设备时区显示', en: 'times in device timezone');
  }
  final h = day.zone.inHours;
  final sign = h >= 0 ? '+' : '−';
  return tr(
    zh: '按经度估算 UTC$sign${h.abs()} 显示,未计夏令时',
    en: 'shown in UTC$sign${h.abs()} (estimated from longitude, no DST)',
  );
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.store, required this.day});

  final DayLight day;
  final LocationStore store;

  @override
  Widget build(BuildContext context) {
    final ns = store.activeLat! >= 0 ? 'N' : 'S';
    final ew = store.activeLon! >= 0 ? 'E' : 'W';
    final coord =
        '${store.activeLat!.abs().toStringAsFixed(3)}°$ns, ${store.activeLon!.abs().toStringAsFixed(3)}°$ew';
    // 'Current location' is the store's persisted sentinel; translate only at
    // display time so the stored JSON stays locale-independent.
    final isHere = store.activeName == 'Current location';
    return Row(
      children: [
        Icon(isHere ? Icons.my_location : Icons.place, size: 18,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  isHere
                      ? tr(zh: '当前位置', en: 'Current location')
                      : store.activeName,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
              Text(
                isHere ? coord : '$coord · ${_zoneNote(day)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoseLegend extends StatelessWidget {
  const _RoseLegend({required this.heading});
  final double? heading;
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 4,
      children: [
        _dot(kGoldenAmber, tr(zh: '太阳', en: 'Sun'), style),
        _dot(kDuskRose, tr(zh: '日落方向', en: 'Sunset dir'), style),
        _dot(Theme.of(context).colorScheme.primary, tr(zh: '月亮', en: 'Moon'), style),
        Text(
            heading != null
                ? tr(zh: '罗盘已对齐你的朝向', en: 'Rose aligned to your heading')
                : tr(zh: '正北朝上', en: 'North up'),
            style: style),
      ],
    );
  }

  Widget _dot(Color c, String label, TextStyle? style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: style),
        ],
      );
}

class _NowRow extends StatelessWidget {
  const _NowRow({required this.sun, required this.moon});
  final SkyPosition sun;
  final SkyPosition moon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _bodyChip(context, tr(zh: '☀︎ 当前太阳', en: '☀︎ Sun now'), sun,
                kGoldenAmber)),
        const SizedBox(width: 12),
        Expanded(
            child: _bodyChip(context, tr(zh: '☾ 当前月亮', en: '☾ Moon now'), moon,
                Theme.of(context).colorScheme.primary)),
      ],
    );
  }

  Widget _bodyChip(BuildContext context, String title, SkyPosition p, Color color) {
    final below = p.altitude < 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          const SizedBox(height: 6),
          Text(
              below
                  ? tr(zh: '在地平线下', en: 'Below horizon')
                  : tr(
                      zh: '高度 ${p.altitude.toStringAsFixed(0)}°',
                      en: 'Alt ${p.altitude.toStringAsFixed(0)}°'),
              style: Theme.of(context).textTheme.titleMedium),
          Text(
              tr(
                  zh: '方位 ${p.azimuth.toStringAsFixed(0)}° ${compassLabel(p.azimuth)}',
                  en: 'Az ${p.azimuth.toStringAsFixed(0)}° ${compassLabel(p.azimuth)}'),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.day, required this.now});
  final DayLight day;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (day.polarNight) {
      return _banner(
          context,
          Icons.dark_mode,
          tr(zh: '极夜', en: 'Polar night'),
          tr(
              zh: '在该地点和日期,太阳整天都在地平线以下。',
              en: 'The Sun stays below the horizon all day at this location and date.'));
    }
    if (day.polarDay) {
      return _banner(
          context,
          Icons.wb_sunny,
          tr(zh: '极昼(午夜太阳)', en: 'Midnight sun'),
          tr(
              zh: '在该地点和日期,太阳整天不落——金色的光线长时间徘徊在地平线附近。',
              en: 'The Sun never sets at this location and date — golden light lingers near the horizon.'));
    }

    final rows = <Widget>[
      _row(context, Icons.brightness_3, tr(zh: '晨光初现', en: 'First light'),
          tr(zh: '蓝调时刻开始', en: 'Blue hour begins'), day.dawnCivil),
      _row(context, Icons.brightness_4, tr(zh: '黄金时段', en: 'Golden hour'),
          tr(zh: '早晨开始', en: 'Morning starts'), day.goldenStartAm),
      _row(context, Icons.wb_twilight, tr(zh: '日出', en: 'Sunrise'),
          _azText(day.sunrise), day.sunrise, highlight: true),
      _row(context, Icons.wb_sunny_outlined,
          tr(zh: '黄金时段结束', en: 'Golden hour ends'),
          tr(zh: '早晨', en: 'Morning'), day.goldenEndAm),
      _noonRow(context),
      _row(context, Icons.wb_sunny_outlined, tr(zh: '黄金时段', en: 'Golden hour'),
          tr(zh: '傍晚开始', en: 'Evening starts'), day.goldenStartPm),
      _row(context, Icons.wb_twilight, tr(zh: '日落', en: 'Sunset'),
          _azText(day.sunset), day.sunset, highlight: true),
      _row(context, Icons.brightness_4,
          tr(zh: '黄金时段结束', en: 'Golden hour ends'),
          tr(zh: '蓝调时刻开始', en: 'Blue hour begins'), day.goldenEndPm),
      _row(context, Icons.brightness_3, tr(zh: '最后天光', en: 'Last light'),
          tr(zh: '夜晚开始', en: 'Night begins'), day.duskCivil),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: rows),
    );
  }

  String _azText(LightMoment m) => m.azimuth == null
      ? ''
      : tr(
          zh: '太阳方位 ${m.azimuth!.toStringAsFixed(0)}° ${compassLabel(m.azimuth!)}',
          en: 'Sun at ${m.azimuth!.toStringAsFixed(0)}° ${compassLabel(m.azimuth!)}');

  Widget _noonRow(BuildContext context) {
    final t = day.solarNoon;
    return _tile(
      context,
      Icons.light_mode,
      tr(zh: '正午', en: 'Solar noon'),
      day.noonAltitude != null
          ? tr(
              zh: '太阳最高仰角 ${day.noonAltitude!.toStringAsFixed(0)}°',
              en: 'Sun peaks at ${day.noonAltitude!.toStringAsFixed(0)}°')
          : '',
      t == null ? '—' : _fmt(t),
      false,
      _isPast(t),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String subtitle,
      LightMoment m, {bool highlight = false}) {
    return _tile(context, icon, title, subtitle, m.time == null ? '—' : _fmt(m.time!),
        highlight, _isPast(m.time));
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle,
      String value, bool highlight, bool past) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: past ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20,
                color: highlight ? kGoldenAmber : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                    color: highlight
                        ? kGoldenAmber
                        : Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  bool _isPast(DateTime? t) =>
      t != null && now != null && day.instantOf(t).isBefore(now!);

  /// "23:58", or "00:04 +1" when the event belongs to the next calendar
  /// day (midnight sun) — so a photographer in Reykjavik in June is not
  /// told the Sun sets before it rises.
  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final off = day.dayOffset(t);
    if (off == 0) return '$h:$m';
    return '$h:$m ${off > 0 ? '+' : '−'}${off.abs()}';
  }

  Widget _banner(BuildContext context, IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoonCard extends StatelessWidget {
  const _MoonCard({required this.phase, required this.times, required this.pro});
  final MoonPhase phase;
  final MoonTimes times;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(_glyph(phase), style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_phaseLabel(phase.name),
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    tr(
                        zh: '照亮 ${(phase.illumination * 100).round()}%'
                            '${phase.waxing ? ' · 渐盈' : ' · 渐亏'}',
                        en: '${(phase.illumination * 100).round()}% illuminated'
                            '${phase.waxing ? ' · waxing' : ' · waning'}'),
                    style: Theme.of(context).textTheme.bodySmall),
                if (pro) ...[
                  const SizedBox(height: 4),
                  Text(
                    tr(
                        zh: '月升 ${_fmt(times.rise)} · 月落 ${_fmt(times.set)}',
                        en: 'Moonrise ${_fmt(times.rise)} · Moonset ${_fmt(times.set)}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// astro.dart keeps the English phase names as stable keys (also used by
  /// [_glyph]); translate only at display time.
  String _phaseLabel(String name) {
    switch (name) {
      case 'New Moon':
        return tr(zh: '新月', en: name);
      case 'Waxing Crescent':
        return tr(zh: '娥眉月', en: name);
      case 'First Quarter':
        return tr(zh: '上弦月', en: name);
      case 'Waxing Gibbous':
        return tr(zh: '盈凸月', en: name);
      case 'Full Moon':
        return tr(zh: '满月', en: name);
      case 'Waning Gibbous':
        return tr(zh: '亏凸月', en: name);
      case 'Last Quarter':
        return tr(zh: '下弦月', en: name);
      case 'Waning Crescent':
        return tr(zh: '残月', en: name);
      default:
        return name;
    }
  }

  String _glyph(MoonPhase p) {
    switch (p.name) {
      case 'New Moon':
        return '🌑';
      case 'Waxing Crescent':
        return '🌒';
      case 'First Quarter':
        return '🌓';
      case 'Waxing Gibbous':
        return '🌔';
      case 'Full Moon':
        return '🌕';
      case 'Waning Gibbous':
        return '🌖';
      case 'Last Quarter':
        return '🌗';
      default:
        return '🌘';
    }
  }
}

class _NoLocation extends StatelessWidget {
  const _NoLocation({this.onSet});
  final VoidCallback? onSet;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_outlined, size: 56,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(tr(zh: '设置一个机位', en: 'Set a location'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr(
                  zh: 'GoldenScout 需要一个位置才能计算光线。'
                      '使用当前 GPS 定位,或添加一个拍摄机位。',
                  en: 'GoldenScout needs a location to compute the light. '
                      'Use your current GPS position or add a shooting spot.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onSet,
              icon: const Icon(Icons.place),
              label: Text(tr(zh: '选择机位', en: 'Choose location')),
            ),
          ],
        ),
      ),
    );
  }
}
