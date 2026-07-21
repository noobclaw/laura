import 'dart:async';

import 'package:flutter/material.dart';

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
    final day = computeDayLight(widget.date, lat, lon);
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
            _LocationHeader(store: store),
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
            _MoonCard(phase: phase, times: computeMoonTimes(widget.date, lat, lon), pro: store.pro),
          ],
        );
      },
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.store});
  final LocationStore store;

  @override
  Widget build(BuildContext context) {
    final ns = store.activeLat! >= 0 ? 'N' : 'S';
    final ew = store.activeLon! >= 0 ? 'E' : 'W';
    final coord =
        '${store.activeLat!.abs().toStringAsFixed(3)}°$ns, ${store.activeLon!.abs().toStringAsFixed(3)}°$ew';
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
              Text(store.activeName,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
              Text(
                isHere ? coord : '$coord · times in device timezone',
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
        _dot(const Color(0xFFF5A623), 'Sun', style),
        _dot(const Color(0xFFD86B4A), 'Sunset dir', style),
        _dot(Theme.of(context).colorScheme.primary, 'Moon', style),
        Text(heading != null ? 'Rose aligned to your heading' : 'North up',
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
        Expanded(child: _bodyChip(context, '☀︎ Sun now', sun, const Color(0xFFF5A623))),
        const SizedBox(width: 12),
        Expanded(child: _bodyChip(context, '☾ Moon now', moon, Theme.of(context).colorScheme.primary)),
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
          Text(below ? 'Below horizon' : 'Alt ${p.altitude.toStringAsFixed(0)}°',
              style: Theme.of(context).textTheme.titleMedium),
          Text('Az ${p.azimuth.toStringAsFixed(0)}° ${compassLabel(p.azimuth)}',
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
      return _banner(context, Icons.dark_mode, 'Polar night',
          'The Sun stays below the horizon all day at this location and date.');
    }
    if (day.polarDay) {
      return _banner(context, Icons.wb_sunny, 'Midnight sun',
          'The Sun never sets at this location and date — golden light lingers near the horizon.');
    }

    final rows = <Widget>[
      _row(context, Icons.brightness_3, 'First light', 'Blue hour begins', day.dawnCivil),
      _row(context, Icons.brightness_4, 'Golden hour', 'Morning starts', day.goldenStartAm),
      _row(context, Icons.wb_twilight, 'Sunrise', _azText(day.sunrise), day.sunrise, highlight: true),
      _row(context, Icons.wb_sunny_outlined, 'Golden hour ends', 'Morning', day.goldenEndAm),
      _noonRow(context),
      _row(context, Icons.wb_sunny_outlined, 'Golden hour', 'Evening starts', day.goldenStartPm),
      _row(context, Icons.wb_twilight, 'Sunset', _azText(day.sunset), day.sunset, highlight: true),
      _row(context, Icons.brightness_4, 'Golden hour ends', 'Blue hour begins', day.goldenEndPm),
      _row(context, Icons.brightness_3, 'Last light', 'Night begins', day.duskCivil),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: rows),
    );
  }

  String _azText(LightMoment m) =>
      m.azimuth == null ? '' : 'Sun at ${m.azimuth!.toStringAsFixed(0)}° ${compassLabel(m.azimuth!)}';

  Widget _noonRow(BuildContext context) {
    final t = day.solarNoon;
    return _tile(
      context,
      Icons.light_mode,
      'Solar noon',
      day.noonAltitude != null ? 'Sun peaks at ${day.noonAltitude!.toStringAsFixed(0)}°' : '',
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
                color: highlight ? const Color(0xFFF5A623) : scheme.onSurfaceVariant),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  bool _isPast(DateTime? t) => t != null && now != null && t.isBefore(now!);

  String _fmt(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
                Text(phase.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${(phase.illumination * 100).round()}% illuminated'
                    '${phase.waxing ? ' · waxing' : ' · waning'}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (pro) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Moonrise ${_fmt(times.rise)} · Moonset ${_fmt(times.set)}',
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
            Text('Set a location', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'GoldenScout needs a location to compute the light. '
              'Use your current GPS position or add a shooting spot.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onSet,
              icon: const Icon(Icons.place),
              label: const Text('Choose location'),
            ),
          ],
        ),
      ),
    );
  }
}
