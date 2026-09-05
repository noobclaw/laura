import 'dart:io';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'job_runner.dart';
import 'lift_screen.dart';
import 'media.dart';
import 'models.dart';
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _HeroCard(onPick: _pick, busy: _picking),
            const SizedBox(height: 14),
            _QuotaCard(store: store),
            const SizedBox(height: 28),
            Row(
              children: [
                Text(tr(zh: '最近修复', en: 'Recent'), style: text.titleLarge),
                const Spacer(),
                if (store.history.isNotEmpty)
                  Text('${store.history.length}',
                      style: text.labelLarge
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            if (store.history.isEmpty)
              const _EmptyHistory()
            else
              _HistoryGrid(store: store),
          ],
        );
      },
    );
  }
}

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
              color: cs.primary.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(zh: '让老照片重新清晰', en: 'Bring old photos back'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(zh: 'AI 放大 · 降噪 · 全程离线', en: 'AI upscale · denoise · fully offline'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cs.primary,
                minimumSize: const Size(0, 54),
              ),
              onPressed: busy ? null : onPick,
              icon: busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tr(zh: '选择照片', en: 'Choose a photo')),
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
        color: Colors.white.withValues(alpha: 0.16),
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
          leading: Icon(Icons.workspace_premium, color: cs.primary),
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
                        Container(
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
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer.withValues(alpha: 0.6),
            ),
            child: Icon(Icons.photo_library_outlined, color: cs.primary, size: 34),
          ),
          const SizedBox(height: 16),
          Text(tr(zh: '还没有修复过的照片', en: 'Nothing restored yet'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            tr(
              zh: '找一张模糊的翻拍或扫描老照片试试,\n半分钟就能看到前后对比。',
              en: 'Try a blurry scan or re-photographed print —\nyou\'ll see a before/after in about half a minute.',
            ),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: store.history.length,
      itemBuilder: (context, i) {
        final r = store.history[i];
        final file = File(store.outputPath(r));
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ResultScreen(record: r, store: store, fresh: false),
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
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${r.scale}x${r.engine == EngineKind.dartFallback ? ' ·' : ''}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
