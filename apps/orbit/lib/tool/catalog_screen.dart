import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';

/// The target library: what Orbit can track, how fresh each object's elements
/// are, and the two knobs that shape the forecast.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({
    super.key,
    required this.store,
    required this.onImport,
  });

  final OrbitStore store;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = store.catalog;
    final now = DateTime.now();
    final free = all.where((e) => e.featured).toList();
    final rest = all.where((e) => !e.featured).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _DataCard(store: store, onImport: onImport),
        const SizedBox(height: 16),
        _ForecastCard(store: store),
        const SizedBox(height: 16),
        _GroupHeader(
          title: tr(zh: '精选目标', en: 'Headliners'),
          caption: tr(
            zh: '免费版追踪这 ${free.length} 个 —— 都是肉眼能认出来的大家伙',
            en: 'Free tier tracks these ${free.length} — the ones you can actually pick out by eye',
          ),
        ),
        for (final e in free) _SatRow(entry: e, now: now, locked: false),
        const SizedBox(height: 20),
        _GroupHeader(
          title: tr(zh: '完整目录', en: 'Full catalogue'),
          caption: store.pro
              ? tr(
                  zh: '${rest.length} 个亮目标,已全部解锁',
                  en: '${rest.length} bright objects, all unlocked',
                )
              : tr(
                  zh: '另外 ${rest.length} 个亮目标 —— 火箭末级、遥感卫星等,Pro 解锁',
                  en: '${rest.length} more bright objects — spent rocket stages, remote-sensing craft. Pro unlocks them.',
                ),
          trailing: store.pro
              ? null
              : TextButton(
                  onPressed: () => showProSheet(context, store),
                  child: Text(tr(zh: '解锁', en: 'Unlock')),
                ),
        ),
        for (final e in rest.take(store.pro ? rest.length : 24))
          _SatRow(
            entry: e,
            now: now,
            locked: !store.pro,
            onLockedTap: () => showProSheet(context, store),
          ),
        if (!store.pro && rest.length > 24)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              tr(
                zh: '…以及另外 ${rest.length - 24} 个目标',
                en: '…and ${rest.length - 24} more targets',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.store, required this.onImport});

  final OrbitStore store;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr(zh: '轨道数据', en: 'Orbital data'),
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                FreshnessChip(ageDays: store.catalogAgeDays, compact: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: tr(zh: '目录目标', en: 'CATALOGUED'),
                    value: '${store.catalog.length}',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: tr(zh: '可追踪', en: 'TRACKABLE'),
                    value: '${store.trackable.length}',
                    accent: kOrbitCyan,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: tr(zh: '精度', en: 'ACCURACY'),
                    value: freshnessLabel(store.freshness),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr(
                zh: '轨道根数会随时间失准。Orbit 不联网,所以更新靠你从公开来源复制一段文本粘进来 —— 三十秒的事。',
                en: 'Element sets go stale. Orbit never goes online, so refreshing means copying a block of public text and pasting it in — about thirty seconds\' work.',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onImport,
                icon: const Icon(Icons.content_paste_go, size: 18),
                label: Text(tr(zh: '更新轨道数据', en: 'Update orbital data')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.store});
  final OrbitStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = store.pro ? const [1, 2, 3, 5, 7, 10] : const [1, 2];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(zh: '预报范围', en: 'Forecast range'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final d in options)
                  ChoiceChip(
                    selected: store.windowDays == d,
                    // Disabled mid-search: each tap starts a full propagation
                    // run, and impatient double-taps used to stack them up.
                    onSelected:
                        store.searching ? null : (_) => store.setWindowDays(d),
                    selectedColor: kOrbitCyan.withValues(alpha: 0.22),
                    checkmarkColor: kOrbitCyan,
                    label: Text(tr(zh: '$d 天', en: '${d}d')),
                  ),
                if (!store.pro)
                  ActionChip(
                    avatar: const Icon(Icons.lock_outline, size: 15),
                    onPressed: () => showProSheet(context, store),
                    label: Text(tr(zh: '最多 10 天', en: 'up to 10d')),
                  ),
              ],
            ),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: store.pro && store.includeDarkPasses,
              onChanged: store.searching
                  ? null
                  : (store.pro
                      ? store.setIncludeDarkPasses
                      : (_) => showProSheet(context, store)),
              secondary: Icon(
                store.pro ? Icons.dark_mode_outlined : Icons.lock_outline,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(
                tr(zh: '包含暗过境', en: 'Include dark passes'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              subtitle: Text(
                tr(
                  zh: '连同地影中、天没黑透的过境一起列出,仰角门槛降到 5°。追无线电或架设备时有用。',
                  en: 'Also list eclipsed and twilight passes, and drop the elevation floor to 5°. Useful for radio work and tracking mounts.',
                ),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.caption,
    this.trailing,
  });

  final String title;
  final String caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  caption,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SatRow extends StatelessWidget {
  const _SatRow({
    required this.entry,
    required this.now,
    required this.locked,
    this.onLockedTap,
  });

  final SatEntry entry;
  final DateTime now;
  final bool locked;

  /// A dimmed, padlocked row reads as tappable; it must lead to the paywall
  /// rather than do nothing (acceptance item 6).
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final age = entry.tle.ageInDays(now);
    final level = freshnessOf(age);
    final ageColor = switch (level) {
      ElementFreshness.fresh => kOrbitCyan,
      ElementFreshness.aging => kSignalAmber,
      ElementFreshness.stale => scheme.error,
    };

    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: locked ? onLockedTap : null,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                locked
                    ? Icons.lock_outline
                    : (entry.featured ? Icons.star : Icons.satellite_alt),
                size: 18,
                color: entry.featured && !locked ? kSignalAmber : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (entry.imported)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.download_done, size: 14, color: kOrbitCyan),
                ),
              Text(
                tr(zh: '${age.round()} 天', en: '${age.round()}d'),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: ageColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        ),
        ),
      ),
    );
  }
}
