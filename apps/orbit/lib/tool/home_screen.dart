import 'dart:async';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'pass_detail_screen.dart';
import 'sky_painters.dart';
import 'store.dart';
import 'ui_common.dart';

/// The forecast screen: one hero answering "when do I go outside", then the
/// timetable behind it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onNeedSite,
    required this.onNeedUpdate,
    required this.onAlign,
  });

  final OrbitStore store;
  final VoidCallback onNeedSite;
  final VoidCallback onNeedUpdate;
  final void Function(SatPass pass) onAlign;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final store = widget.store;

    if (!store.hasSite) {
      return EmptyState(
        icon: Icons.my_location,
        title: tr(zh: '先给 Orbit 一个观测点', en: 'Orbit needs a place to watch from'),
        body: tr(
          zh: '过境时刻取决于你站在地球的哪一点。设定观测点后,Orbit 会算出未来几天头顶所有可见卫星,全程离线。',
          en: 'When a satellite passes depends on where you stand. Set your observing site and Orbit works out every visible pass overhead — all on this device.',
        ),
        action: FilledButton.icon(
          onPressed: widget.onNeedSite,
          icon: const Icon(Icons.place_outlined),
          label: Text(tr(zh: '设定观测点', en: 'Set observing site')),
        ),
      );
    }

    if (store.searching && store.passes.isEmpty) {
      return _SearchingState(store: store);
    }

    final grouped = _groupByDay(store.passes);

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // A recompute with results already on screen used to be completely
          // silent: the user tapped "7 days", nothing moved, and they tapped
          // again — starting another full search.
          if (store.searching)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (store.loadError != null) _ErrorBanner(message: store.loadError!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _Hero(
              store: store,
              onAlign: widget.onAlign,
              onNeedUpdate: widget.onNeedUpdate,
            ),
          ),
          if (store.freshness == ElementFreshness.stale)
            _StaleBanner(onUpdate: widget.onNeedUpdate),
          if (store.searchError != null) _ErrorBanner(message: store.searchError!),
          if (store.passes.isEmpty)
            _NoPasses(store: store, onNeedUpdate: widget.onNeedUpdate)
          else
            for (final entry in grouped.entries) ...[
              SectionHeader(
                formatDayHeader(entry.key),
                trailing: Text(
                  tr(
                    zh: '${entry.value.length} 次',
                    en: '${entry.value.length} pass${entry.value.length == 1 ? '' : 'es'}',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              for (final pass in entry.value)
                _PassCard(
                  pass: pass,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PassDetailScreen(
                        pass: pass,
                        store: widget.store,
                        onAlign: widget.onAlign,
                      ),
                    ),
                  ),
                ),
            ],
          if (store.passesTruncated && store.passes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Text(
                tr(
                  zh: '列表已满 ${store.passes.length} 条,只显示到 '
                      '${formatDayHeader(store.passes.last.start)} '
                      '${formatClock(store.passes.last.start)} 为止。缩短预报天数可以看得更全。',
                  en: 'List is capped at ${store.passes.length} entries, running only to '
                      '${formatDayHeader(store.passes.last.start)} '
                      '${formatClock(store.passes.last.start)}. Shorten the forecast window to see a complete range.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ),
          const SizedBox(height: 14),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FreshnessChip(ageDays: store.catalogAgeDays),
            ),
          ),
        ],
      ),
    );
  }

  Map<DateTime, List<SatPass>> _groupByDay(List<SatPass> passes) {
    final map = <DateTime, List<SatPass>>{};
    for (final p in passes) {
      final day = DateTime(p.start.year, p.start.month, p.start.day);
      map.putIfAbsent(day, () => []).add(p);
    }
    return map;
  }
}

class _Hero extends StatefulWidget {
  const _Hero({
    required this.store,
    required this.onAlign,
    required this.onNeedUpdate,
  });

  final OrbitStore store;
  final void Function(SatPass) onAlign;
  final VoidCallback onNeedUpdate;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Only the countdown needs a second hand, so only the hero subtree rebuilds
    // on it — the list below is static between searches.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final pass = store.nextPass;
    final brightness = Theme.of(context).brightness;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(gradient: skyGradient(brightness)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const StarFieldPainter(seed: 42, count: 90),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: pass == null
                  ? _HeroEmpty(store: store, onNeedUpdate: widget.onNeedUpdate)
                  : _HeroPass(pass: pass, onAlign: widget.onAlign),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPass extends StatelessWidget {
  const _HeroPass({required this.pass, required this.onAlign});

  final SatPass pass;
  final void Function(SatPass) onAlign;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final running = pass.start.isBefore(now);
    final remaining = (running ? pass.end : pass.start).difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                pass.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            VisibilityBadge(
                visibility: pass.visibility,
                magnitude: pass.brightestMagnitude),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          running
              ? tr(zh: '正在过境 · 还剩', en: 'Passing now · time left')
              : tr(zh: '下一次过境还有', en: 'Next pass in'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                letterSpacing: 0.6,
              ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatCountdown(remaining),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    height: 1.05,
                  ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                tr(
                  zh: '${formatClock(pass.start)} 起',
                  en: 'from ${formatClock(pass.start)}',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: kSignalAmber,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: tr(zh: '路径', en: 'PATH'),
                value:
                    '${compassPointOf(pass.startAzimuth)} → ${compassPointOf(pass.endAzimuth)}',
                onLight: true,
              ),
            ),
            Expanded(
              child: StatTile(
                label: tr(zh: '最高', en: 'PEAK'),
                value: formatElevation(pass.peakElevation),
                accent: kSignalAmber,
                onLight: true,
              ),
            ),
            Expanded(
              child: StatTile(
                label: tr(zh: '时长', en: 'DURATION'),
                value: formatDuration(pass.duration),
                onLight: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => onAlign(pass),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.explore_outlined, size: 20),
            label: Text(tr(zh: '抬头对准它', en: 'Point me at it')),
          ),
        ),
      ],
    );
  }
}

class _HeroEmpty extends StatelessWidget {
  const _HeroEmpty({required this.store, required this.onNeedUpdate});

  final OrbitStore store;
  final VoidCallback onNeedUpdate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.nights_stay_outlined,
            color: Colors.white.withValues(alpha: 0.85), size: 30),
        const SizedBox(height: 14),
        Text(
          tr(zh: '这几天头顶很安静', en: 'A quiet few nights overhead'),
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            zh: '未来 ${store.windowDays} 天内,你的位置上没有够亮、够高的可见过境。',
            en: 'No bright, high-enough visible passes over your site in the next ${store.windowDays} day(s).',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

class _PassCard extends StatelessWidget {
  const _PassCard({required this.pass, required this.onTap});

  final SatPass pass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 40,
                  child: CustomPaint(
                    painter: PassArcPainter(
                      peakElevation: pass.peakElevation,
                      startAzimuth: pass.startAzimuth,
                      endAzimuth: pass.endAzimuth,
                      visibility: pass.visibility,
                      scheme: scheme,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pass.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatClock(pass.start)} → ${formatClock(pass.end)}  ·  '
                        '${compassPointOf(pass.startAzimuth)}→${compassPointOf(pass.endAzimuth)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 7),
                      VisibilityBadge(
                        visibility: pass.visibility,
                        magnitude: pass.brightestMagnitude,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatElevation(pass.peakElevation),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: pass.visible ? kSignalAmber : scheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      tr(zh: '最高', en: 'peak'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchingState extends StatelessWidget {
  const _SearchingState({required this.store});
  final OrbitStore store;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            tr(zh: '正在推演轨道…', en: 'Propagating orbits…'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              zh: '${store.trackable.length} 个目标 × ${store.windowDays} 天,全部在这台设备上算',
              en: '${store.trackable.length} targets over ${store.windowDays} day(s), computed on this device',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _NoPasses extends StatelessWidget {
  const _NoPasses({required this.store, required this.onNeedUpdate});

  final OrbitStore store;
  final VoidCallback onNeedUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(zh: '可以试试这些', en: 'Things to try'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              if (_polarSummerNight(store))
                _Tip(tr(
                  zh: '你所在的纬度这个季节夜里天不会全黑，所以本就没有肉眼可见的过境。打开“包含暗过境”才看得到头顶的卫星。',
                  en: 'At your latitude the sky never gets properly dark this time of year, so there are genuinely no naked-eye passes. Turn on "include dark passes" to see what is overhead anyway.',
                )),
              _Tip(tr(
                zh: '把预报天数拉长——可见过境很挑时段,常常集中在日出前和日落后一两个小时。',
                en: 'Widen the forecast window — visible passes cluster in the hour or two after dusk and before dawn.',
              )),
              _Tip(tr(
                zh: 'Pro 可以解锁全部 ${store.catalog.length} 个目标,而不只是 8 个精选。',
                en: 'Pro unlocks all ${store.catalog.length} catalogued targets instead of the 8 headliners.',
              )),
              if (store.freshness != ElementFreshness.fresh)
                _Tip(tr(
                  zh: '轨道数据已经有 ${store.catalogAgeDays.round()} 天了,更新一下会更准。',
                  en: 'Your orbital elements are ${store.catalogAgeDays.round()} days old — refreshing them helps.',
                )),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onNeedUpdate,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(tr(zh: '更新轨道数据', en: 'Update orbital data')),
                ),
              ),
              Text(
                tr(
                  zh: '提示:Orbit 从不联网,更新靠你粘贴一段公开的轨道根数。',
                  en: 'Orbit never goes online — updating means pasting in public element sets.',
                ),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Above roughly 55 degrees the summer sky never reaches civil twilight, so a
/// visible-only forecast is legitimately empty and every generic suggestion
/// ("widen the window", "unlock more targets") is a dead end.
bool _polarSummerNight(OrbitStore store) {
  final lat = store.site?.latitude;
  if (lat == null || lat.abs() < 55) return false;
  final month = DateTime.now().month;
  final northernSummer = month >= 4 && month <= 8;
  return lat > 0 ? northernSummer : !northernSummer;
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                  color: kOrbitCyan, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onUpdate});
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onUpdate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.update, size: 20, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(
                      zh: '轨道数据已超过 30 天,过境时刻可能偏差几分钟。点这里更新。',
                      en: 'Orbital data is over 30 days old — times may drift by minutes. Tap to update.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                          height: 1.35,
                        ),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onErrorContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(zh: '计算过境时出错:$message', en: 'Pass computation failed: $message'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
