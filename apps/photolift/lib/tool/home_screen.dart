import 'dart:io';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'job_runner.dart';
import 'lift_screen.dart';
import 'media.dart';
import 'models.dart';
import 'pixel_art.dart';
import 'pro.dart';
import 'result_screen.dart';
import 'store.dart';

/// Home: the hero "pick a photo" card, today's free allowance, and the grid
/// of photos already restored.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.runner});

  final PhotoLiftStore store;
  final LiftJobRunner runner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _picking = false;

  /// Mirror of `store.history` that the AnimatedGrid animates towards —
  /// the grid must be told about each insert / remove, not handed a new list.
  final List<LiftRecord> _shown = [];
  final GlobalKey<SliverAnimatedGridState> _gridKey = GlobalKey<SliverAnimatedGridState>();

  @override
  void initState() {
    super.initState();
    _shown.addAll(widget.store.history);
    widget.store.addListener(_syncHistory);
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncHistory);
    super.dispose();
  }

  Duration get _gridDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 380);

  void _syncHistory() {
    if (!mounted) return;
    final next = widget.store.history;
    final grid = _gridKey.currentState;
    final changed = next.length != _shown.length ||
        Iterable<int>.generate(next.length).any((i) => next[i].id != _shown[i].id);
    if (!changed) return;
    if (grid == null) {
      // Grid not mounted yet (store still loading): just mirror.
      _shown
        ..clear()
        ..addAll(next);
      return;
    }
    final nextIds = {for (final r in next) r.id};
    for (var i = _shown.length - 1; i >= 0; i--) {
      final r = _shown[i];
      if (nextIds.contains(r.id)) continue;
      _shown.removeAt(i);
      grid.removeItem(
        i,
        (context, anim) => _HistoryTile(record: r, store: widget.store, animation: anim),
        duration: _gridDuration,
      );
    }
    final shownIds = {for (final r in _shown) r.id};
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (shownIds.contains(r.id)) continue;
      _shown.insert(i, r);
      grid.insertItem(i, duration: _gridDuration);
    }
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final photo = await MediaBridge.pick();
      if (photo == null || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LiftScreen(photo: photo, store: widget.store, runner: widget.runner),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeUpscaleError(e))));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final text = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverList.list(
                children: [
                  _HeroCard(onPick: _pick, busy: _picking),
                  const SizedBox(height: 14),
                  _QuotaCard(store: store),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(tr(zh: '最近修复', en: 'Recent'), style: text.titleLarge),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _shown.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey(_shown.length),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('${_shown.length}',
                                    style: text.labelLarge?.copyWith(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w700)),
                              ),
                      ),
                    ],
                  ),
                  // The empty state lives above the (then 0-item) grid so the
                  // grid stays mounted and the very first result animates in.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _shown.isEmpty
                        ? const _EmptyHistory(key: ValueKey('empty'))
                        : const SizedBox.shrink(key: ValueKey('grid')),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverAnimatedGrid(
                key: _gridKey,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                initialItemCount: _shown.length,
                itemBuilder: (context, i, anim) => _HistoryTile(
                  record: _shown[i],
                  store: store,
                  animation: anim,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The hero: rose→wine gradient, the tagline, and the signature
/// "pixels resolving" mosaic looping on the right. The CTA is a white pill
/// with press-scale feedback and an animated busy state.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onPick, required this.busy});
  final VoidCallback onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(cs),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFB8204F).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(zh: '让老照片\n重新清晰', en: 'Bring old\nphotos back'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(zh: 'AI 放大 · 降噪 · 全程离线', en: 'AI upscale · denoise · fully offline'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const SizedBox(
                width: 108,
                height: 108,
                child: ExcludeSemantics(child: PixelResolve(gap: 2.5, radius: 3.5)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(tr(zh: '2x / 4x 放大', en: '2x / 4x upscale')),
              _Pill(tr(zh: '照片不离开手机', en: 'Photos stay on device')),
              _Pill(tr(zh: '无订阅', en: 'No subscription')),
            ],
          ),
          const SizedBox(height: 20),
          PressScale(
            enabled: !busy,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB8204F),
                  minimumSize: const Size(0, 54),
                ),
                onPressed: busy ? null : onPick,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                      child: busy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2))
                          : const Icon(Icons.add_photo_alternate_outlined,
                              key: ValueKey('idle'), size: 22),
                    ),
                    const SizedBox(width: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        busy
                            ? tr(zh: '正在打开相册…', en: 'Opening Photos…')
                            : tr(zh: '选择照片', en: 'Choose a photo'),
                        key: ValueKey(busy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (store.pro) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: kLiftGold),
          title: Text(tr(zh: 'Pro 已解锁', en: 'Pro unlocked'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(tr(zh: '不限张数 · 2x / 4x · 无标签', en: 'Unlimited · 2x / 4x · no tag')),
        ),
      );
    }
    final remaining = store.remainingToday();
    final used = PhotoLiftStore.freeDailyLimit - remaining;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remaining > 0
                        ? tr(zh: '今天还可免费修复 $remaining 张', en: '$remaining free photos left today')
                        : tr(zh: '今天的免费额度已用完', en: 'Today\'s free photos are used up'),
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < PhotoLiftStore.freeDailyLimit; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          width: 26,
                          height: 6,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: i < used ? cs.outlineVariant : cs.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(tr(zh: '免费版 2x · 带角标', en: 'Free: 2x · corner tag'),
                          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showProSheet(context),
              child: Text(tr(zh: '升级 Pro', en: 'Go Pro')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // A tiny static mosaic, half-resolved: "this is what we do".
          SizedBox(
            width: 64,
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: kLiftWine.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: PixelResolve(progress: 0.55, grid: 6, gap: 1.5, radius: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr(zh: '还没有修复过的照片', en: 'Nothing restored yet'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            tr(
              zh: '找一张模糊的翻拍或扫描老照片试试,\n通常一两分钟内就能看到前后对比。',
              en: 'Try a blurry scan or re-photographed print —\nyou\'ll usually see a before/after within a couple of minutes.',
            ),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// One history cell. [animation] is the AnimatedGrid enter/exit progress: a
/// new result scales up from 0.6 and fades in; a deleted one shrinks away.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.store,
    required this.animation,
  });

  final LiftRecord record;
  final PhotoLiftStore store;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = File(store.outputPath(record));
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1).animate(curved),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ResultScreen(record: record, store: store, fresh: false),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: cs.surfaceContainerHighest),
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: (140 * dpr).round(),
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: kLiftGold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${record.scale}x${record.engine == EngineKind.dartFallback ? ' ·' : ''}',
                      style: const TextStyle(
                          color: kLiftWine, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
