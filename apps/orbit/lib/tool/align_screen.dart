import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'astro.dart';
import 'models.dart';
import 'sensors.dart';
import 'sgp4.dart';
import 'sky_painters.dart';
import 'store.dart';
import 'ui_common.dart';

/// "Point me at it" — the screen that closes the gap between a table of numbers
/// and actually finding the thing. Turn until the wedge meets the pointer, raise
/// the phone until the bar centres, look past the top edge.
class AlignScreen extends StatefulWidget {
  const AlignScreen({
    super.key,
    required this.pass,
    required this.store,
    required this.sensors,
  });

  final SatPass pass;
  final OrbitStore store;
  final SensorHub sensors;

  @override
  State<AlignScreen> createState() => _AlignScreenState();
}

class _AlignScreenState extends State<AlignScreen>
    with WidgetsBindingObserver {
  Timer? _tick;
  Sgp4Satellite? _sat;
  SkyFix? _live;
  bool _sensorsHeld = false;

  /// How close counts as aimed. A handheld magnetometer is not better than this
  /// even when calibrated, and uncorrected declination can add several degrees
  /// on top - claiming a tighter lock than that would be theatre.
  static const double _toleranceDeg = 12.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _holdSensors();
    final entry = _findEntry();
    if (entry != null) {
      final s = Sgp4Satellite(entry.tle);
      if (s.usable) _sat = s;
    }
    _recompute();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) _recompute();
    });
  }

  void _holdSensors() {
    if (_sensorsHeld) return;
    _sensorsHeld = true;
    widget.sensors.acquire();
  }

  void _releaseSensors() {
    if (!_sensorsHeld) return;
    _sensorsHeld = false;
    widget.sensors.release();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The magnetometer has no business running while the app is in the
    // background - this app's whole claim is that it does nothing behind
    // your back.
    if (state == AppLifecycleState.resumed) {
      _holdSensors();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _releaseSensors();
    }
  }

  SatEntry? _findEntry() {
    for (final e in widget.store.catalog) {
      if (e.id == widget.pass.satId) return e;
    }
    return null;
  }

  void _recompute() {
    final sat = _sat;
    final site = widget.store.site;
    if (sat == null || site == null) {
      setState(() {});
      return;
    }
    final fix = skyFix(
      sat: sat,
      timeUtc: DateTime.now().toUtc(),
      latDeg: site.latitude,
      lonDeg: site.longitude,
      altKm: site.altitudeKm,
      standardMagnitude: null,
    );
    setState(() => _live = fix);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _releaseSensors();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pass = widget.pass;
    final now = DateTime.now();
    final finished = now.isAfter(pass.end);
    final inProgress = now.isAfter(pass.start) && !finished;
    final live = _live;
    final declination = widget.store.site?.magneticDeclinationDeg ?? 0.0;

    // While the pass is running, aim at where the satellite actually is. Before
    // it starts, aim at the horizon point it will rise from.
    final targetAz =
        inProgress && live != null ? live.look.azimuthDeg : pass.startAzimuth;
    final targetEl = inProgress && live != null
        ? live.look.elevationDeg
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(pass.displayName)),
      body: ListenableBuilder(
        listenable: widget.sensors,
        builder: (context, _) {
          // The compass reads magnetic north; every bearing in this app is
          // measured from true north. Without the user's declination the two
          // frames differ by up to 20 degrees at high latitudes - far more than
          // the tolerance, which would light up "on target" at the wrong sky.
          final rawHeading = widget.sensors.headingDeg;
          final heading =
              rawHeading == null ? null : (rawHeading + declination) % 360.0;
          final pitch = widget.sensors.pitchDeg;
          final azOff = heading == null ? null : bearingDelta(heading, targetAz);
          final elOff = pitch == null ? null : targetEl - pitch;
          final onTarget = !finished &&
              azOff != null &&
              elOff != null &&
              azOff.abs() <= _toleranceDeg &&
              elOff.abs() <= _toleranceDeg;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StatusHeader(
                pass: pass,
                inProgress: inProgress,
                finished: finished,
                onTarget: onTarget,
                now: now,
              ),
              const SizedBox(height: 16),
              // A stretched Row inside a scroll view would be handed an
              // unbounded height and blow up in layout, so the height is derived
              // from the available width instead: the dial takes 5/7 of it and
              // the tilt meter matches whatever that comes to.
              LayoutBuilder(
                builder: (context, constraints) {
                  final dialSize =
                      ((constraints.maxWidth - 14) * 5 / 7).clamp(140.0, 360.0);
                  return SizedBox(
                    height: dialSize,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: CustomPaint(
                            painter: AlignDialPainter(
                              headingDeg: heading ?? 0,
                              targetAzimuthDeg: targetAz,
                              onTarget: onTarget,
                              hasHeading: heading != null,
                              scheme: Theme.of(context).colorScheme,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _PitchMeter(
                            currentPitch: pitch,
                            targetElevation: targetEl,
                            onTarget:
                                elOff != null && elOff.abs() <= _toleranceDeg,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _Guidance(
                heading: heading,
                pitch: pitch,
                targetAz: targetAz,
                targetEl: targetEl,
                azOff: azOff,
                elOff: elOff,
                onTarget: onTarget,
                finished: finished,
                declination: declination,
              ),
              const SizedBox(height: 14),
              _LivePanel(
                live: live,
                pass: pass,
                inProgress: inProgress,
                hasSatellite: _sat != null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.pass,
    required this.inProgress,
    required this.finished,
    required this.onTarget,
    required this.now,
  });

  final SatPass pass;
  final bool inProgress;
  final bool finished;
  final bool onTarget;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = pass.start.difference(now);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration:
            BoxDecoration(gradient: skyGradient(Theme.of(context).brightness)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const StarFieldPainter(seed: 11, count: 45),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  Icon(
                    finished
                        ? Icons.history
                        : (onTarget
                            ? Icons.check_circle
                            : Icons.screen_rotation_alt),
                    color: onTarget ? kSignalAmber : Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          finished
                              ? tr(zh: '这次过境已经结束了', en: 'This pass is over')
                              : onTarget
                                  ? tr(zh: '对准了 —— 就是那个方向', en: 'On target — that way')
                                  : inProgress
                                      ? tr(zh: '正在过境,跟着指针转', en: 'Passing now — follow the pointer')
                                      : tr(zh: '它会从这里升起', en: 'It will rise from here'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          finished
                              ? tr(
                                  zh: '${formatClock(pass.start)}–${formatClock(pass.end)} · 回列表看下一次',
                                  en: '${formatClock(pass.start)}–${formatClock(pass.end)} · go back for the next one',
                                )
                              : inProgress
                                  ? '${formatClock(pass.end)} ${tr(zh: '落下', en: 'sets')}'
                                  : '${formatCountdown(remaining)} · ${formatClock(pass.start)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical tilt gauge: raise or lower the phone until the marker meets the
/// target band.
/// Vertical tilt gauge: raise or lower the phone until the marker meets the
/// target band. Labelled like an instrument, because an unlabelled bar with one
/// stripe in it tells you nothing about how far you still have to go.
class _PitchMeter extends StatelessWidget {
  const _PitchMeter({
    required this.currentPitch,
    required this.targetElevation,
    required this.onTarget,
  });

  final double? currentPitch;
  final double targetElevation;
  final bool onTarget;

  static const double _minDeg = -20;
  static const double _maxDeg = 90;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = onTarget ? kSignalAmber : kOrbitCyan;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
        double toY(double deg) =>
            h * (1.0 - ((deg - _minDeg) / (_maxDeg - _minDeg)).clamp(0.0, 1.0));
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7)),
                ),
              ),
            ),
            // Scale marks, so the distance to the target reads as an angle.
            // 90 is deliberately absent: its label would collide with the
            // gauge's own title at the top of the track.
            for (final deg in const [0, 30, 60])
              Positioned(
                left: 8,
                right: 8,
                top: toY(deg.toDouble()) - 7,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 1,
                      color: scheme.outlineVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$deg°',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontSize: 9,
                          ),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: toY(targetElevation) - 8,
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.28),
                  border: Border.symmetric(
                    horizontal: BorderSide(color: accent, width: 1.5),
                  ),
                ),
              ),
            ),
            if (currentPitch != null)
              Positioned(
                left: 6,
                right: 6,
                top: toY(currentPitch!) - 2,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: Text(
                  currentPitch == null
                      ? tr(zh: '无传感器', en: 'no sensor')
                      : '${currentPitch!.round()}°',
                  style: currentPitch == null
                      ? Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )
                      : Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              child: Center(
                child: Text(
                  tr(zh: '仰角', en: 'TILT'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Guidance extends StatelessWidget {
  const _Guidance({
    required this.heading,
    required this.pitch,
    required this.targetAz,
    required this.targetEl,
    required this.azOff,
    required this.elOff,
    required this.onTarget,
    required this.finished,
    required this.declination,
  });

  final double? heading, pitch, azOff, elOff;
  final double targetAz, targetEl;
  final bool onTarget;
  final bool finished;
  final double declination;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final noSensors = heading == null && pitch == null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: tr(zh: '目标方位', en: 'TARGET BEARING'),
                    value: formatBearing(targetAz),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: tr(zh: '目标仰角', en: 'TARGET ELEVATION'),
                    value: formatElevation(targetEl),
                    accent: kSignalAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (noSensors)
              Text(
                tr(
                  zh: '这台设备没有可用的方位/姿态传感器。照着上面的数字来:面朝${compassPointOf(targetAz)}方向,再抬头约 ${targetEl.round()} 度。',
                  en: 'No usable compass or tilt sensor on this device. Use the numbers instead: face ${compassPointOf(targetAz)}, then look about ${targetEl.round()}° up.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
              )
            else
              Text(
                finished
                    ? tr(
                        zh: '过境已经结束,这里显示的是它当时的路径。',
                        en: 'The pass is over; these are the bearings it took.',
                      )
                    : onTarget
                        ? tr(
                            zh: '保持这个姿势看过去 —— 它应该是一颗匀速滑过、不闪烁的“星”。',
                            en: 'Hold this and look past the top of the phone — you are after a steady "star" gliding at a constant speed, no blinking.',
                      )
                        : _instruction(context),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: onTarget ? kSignalAmber : scheme.onSurface,
                      fontWeight: onTarget ? FontWeight.w600 : null,
                    ),
              ),
            if (!noSensors && declination == 0) ...[
              const SizedBox(height: 12),
              Text(
                SensorHub.magneticNote,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _instruction(BuildContext context) {
    final parts = <String>[];
    if (azOff != null && azOff!.abs() > 8) {
      final deg = azOff!.abs().round();
      parts.add(azOff! > 0
          ? tr(zh: '向右转 $deg°', en: 'turn right $deg°')
          : tr(zh: '向左转 $deg°', en: 'turn left $deg°'));
    }
    if (elOff != null && elOff!.abs() > 8) {
      final deg = elOff!.abs().round();
      parts.add(elOff! > 0
          ? tr(zh: '再抬高 $deg°', en: 'raise $deg° higher')
          : tr(zh: '再放低 $deg°', en: 'lower by $deg°'));
    }
    if (parts.isEmpty) {
      return tr(zh: '快对上了,稳住。', en: 'Almost there — hold steady.');
    }
    return '${parts.join(tr(zh: ',', en: ', '))}${tr(zh: '。', en: '.')}';
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.live,
    required this.pass,
    required this.inProgress,
    required this.hasSatellite,
  });

  final SkyFix? live;
  final SatPass pass;
  final bool inProgress;
  final bool hasSatellite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!hasSatellite) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            tr(
              zh: '这个目标的轨道根数已经不在目录里了(可能是导入的数据被清空)。回到目标库重新导入即可。',
              en: 'This target is no longer in the catalogue (its imported elements may have been cleared). Re-import it from the target library.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ),
      );
    }
    final l = live;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(zh: '此刻它在哪', en: 'Where it is right now'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            if (l == null)
              Text(
                tr(zh: '正在计算…', en: 'Computing…'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: tr(zh: '方位', en: 'AZIMUTH'),
                      value: formatBearing(l.look.azimuthDeg),
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: tr(zh: '仰角', en: 'ELEVATION'),
                      value: formatElevation(l.look.elevationDeg),
                      accent: l.look.elevationDeg > 0 ? kOrbitCyan : null,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: tr(zh: '距离', en: 'RANGE'),
                      value: '${l.look.rangeKm.round()} km',
                    ),
                  ),
                ],
              ),
            if (l != null && l.look.elevationDeg <= 0) ...[
              const SizedBox(height: 12),
              Text(
                tr(
                  zh: '现在它还在地平线以下,先按上面的方位站好等着。',
                  en: 'It is still below your horizon — take up the bearing above and wait.',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
