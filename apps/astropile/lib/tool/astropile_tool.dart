import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';
import 'engine/output.dart';
import 'engine/picker.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'ui/frames_screen.dart';
import 'ui/star_field.dart';
import 'ui/widgets.dart';

/// The stacker: a hero that explains the job in one line, one primary action,
/// and the three steps the app performs. Everything else is behind the flow.
class AstropileTool extends ToolModule {
  AstropileTool();

  final AstroStore store = AstroStore();

  @override
  Widget buildHome(BuildContext context) => _Home(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(Icons.workspace_premium,
                color: Theme.of(context).colorScheme.primary),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: store.pro
                ? Text(tr(
                    zh: '最多 $kProFrameLimit 张 · 中值叠加 · 记住设置',
                    en: 'Up to $kProFrameLimit frames · median stacking · saved settings'))
                : Text(tr(zh: '一次买断,无订阅', en: 'One-time purchase'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: store.pro
                ? null
                // The app theme forces filled buttons to full width
                // (Size.fromHeight); inside ListTile.trailing that makes the
                // tile abort layout, so this one button opts back out.
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 40)),
                    onPressed: () => showProSheet(context),
                    child: const ProPriceText(fallback: kProFallbackPrice),
                  ),
            onTap: store.pro ? null : () => showProSheet(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
        const _ClearScratchTile(),
      ];
}

/// Shows how much scratch space is actually sitting there before offering to
/// clear it — "clear temporary files" with no number is a button nobody can
/// decide about.
class _ClearScratchTile extends StatefulWidget {
  const _ClearScratchTile();

  @override
  State<_ClearScratchTile> createState() => _ClearScratchTileState();
}

class _ClearScratchTileState extends State<_ClearScratchTile> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final b = await WorkDirs.usedBytes();
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(tr(zh: '清理临时文件', en: 'Clear temporary files')),
      subtitle: Text(bytes == null
          ? tr(zh: '正在统计…', en: 'Measuring…')
          : bytes == 0
              ? tr(zh: '没有需要清理的缓存', en: 'Nothing to clear')
              : tr(
                  zh: '叠加过程留下的缓存,当前 ${formatBytes(bytes)}',
                  en: 'Scratch files from previous runs — ${formatBytes(bytes)}',
                )),
      onTap: bytes == null || bytes == 0
          ? null
          : () async {
              await WorkDirs.clearAll();
              if (!context.mounted) return;
              showNotice(context, tr(zh: '已清理', en: 'Cleared'));
              await _measure();
            },
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.store});
  final AstroStore store;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final FrameImporter _importer = FrameImporter();
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    // Leftovers from a run that was interrupted (crash, force-quit). A
    // full-resolution 32-frame run leaves about a gigabyte behind.
    WorkDirs.clearAll();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await _importer.pickFromLibrary();
      if (!mounted) return;
      if (result.error != null) {
        showNotice(
          context,
          result.error!,
          action: result.permissionDenied
              ? SnackBarAction(
                  label: tr(zh: '去设置', en: 'Settings'),
                  onPressed: openSystemSettings,
                )
              : null,
        );
        return;
      }
      // One snackbar, not one per file: showNotice hides the previous one, so
      // a loop would leave only the last reason on screen.
      if (result.skipped.isNotEmpty) {
        final shown = result.skipped.take(3).join('\n');
        final rest = result.skipped.length - 3;
        showNotice(
            context,
            rest > 0
                ? '$shown\n${tr(zh: '另有 $rest 张被跳过', en: '$rest more were skipped')}'
                : shown);
      }
      if (result.frames.isEmpty) return; // cancelled, or nothing usable
      if (result.frames.length < 2) {
        showNotice(
            context,
            tr(
              zh: '叠加至少需要 2 张同一场景的照片。',
              en: 'Stacking needs at least two photos of the same scene.',
            ));
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FramesScreen(
          store: widget.store,
          frames: result.frames,
          scratchDir: result.scratchDir,
        ),
      ));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _Hero(count: widget.store.stackedCount, pro: widget.store.pro),
          const SizedBox(height: 18),
          PressScale(
            enabled: !_picking,
            child: FilledButton(
              onPressed: _picking ? null : _pick,
              child: AnimatedSwitcher(
                duration: animMs(context, 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(sizeFactor: anim, axis: Axis.horizontal, child: child),
                ),
                child: Row(
                  key: ValueKey(_picking),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_picking)
                      const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.add_photo_alternate_outlined),
                    const SizedBox(width: 10),
                    // Flexible, so a wide label at a large text scale wraps
                    // inside the button instead of painting past its edge.
                    Flexible(
                      child: Text(
                        _picking
                            ? tr(zh: '正在读取…', en: 'Reading…')
                            : tr(zh: '选择照片开始叠加', en: 'Pick photos to stack'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              widget.store.pro
                  ? tr(
                      zh: '一次可选 2–$kProFrameLimit 张同一场景的连拍',
                      en: 'Pick 2–$kProFrameLimit shots of the same scene')
                  : tr(
                      zh: '免费版一次可叠 $kFreeFrameLimit 张',
                      en: 'The free tier stacks $kFreeFrameLimit frames at a time'),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(tr(zh: '它做三件事', en: 'What it does'),
                style: text.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const _Step(
            index: 1,
            icon: Icons.center_focus_strong,
            titleZh: '找星点',
            titleEn: 'Finds the stars',
            bodyZh: '在每一张照片上量出星点的位置,亚像素精度。',
            bodyEn: 'Measures where every star sits on every frame, to sub-pixel precision.',
          ),
          const _Step(
            index: 2,
            icon: Icons.grid_goldenratio,
            titleZh: '对齐',
            titleEn: 'Lines them up',
            bodyZh: '用星阵的形状把每一张对到参考帧上,并告诉你对得有多准。',
            bodyEn: 'Matches star patterns onto the reference frame, and tells you how well each one fit.',
          ),
          const _Step(
            index: 3,
            icon: Icons.layers_outlined,
            titleZh: '叠加',
            titleEn: 'Stacks them',
            bodyZh: '逐像素合并,噪点被平均掉,暗处的细节留下来。',
            bodyEn: 'Combines them pixel by pixel: the noise averages away, the faint detail stays.',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(
                    zh: '无网络权限,照片只在这台手机上处理。',
                    en: 'No network permission — photos are processed on this phone only.',
                  ),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.count, required this.pro});
  final int count;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A floor, not a fixed height: at a large text scale the English
    // headline and caption need more than 236 px, and the panel grows with
    // them instead of painting past its own bottom edge.
    return Container(
      constraints: const BoxConstraints(minHeight: 236),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: kSkyGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AstroInk.deep.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          // The sky itself: twinkling stars, a meteor now and then, and the
          // long trails a static camera records — idle, so not converged.
          const Positioned.fill(child: StarField(seed: 7, density: 1.1)),
          // A breath of horizon glow at the bottom edge so the text sits on
          // something, without a flat overlay.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AstroInk.deep.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          // The eyebrow is pinned to the top corner; the copy below sits on
          // the bottom edge and pushes the panel taller when it needs to.
          Positioned(
            left: 22,
            top: 20,
            child: Text(
              pro ? 'ASTROPILE · PRO' : 'ASTROPILE · OFFLINE',
              style: text.labelSmall?.copyWith(
                color: AstroColors.silver.withValues(alpha: 0.7),
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 68, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(zh: '十几张夜空照片\n叠成一张干净的', en: 'A burst of night sky,\nstacked into one clean shot'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall?.copyWith(
                    color: AstroColors.star,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        tr(
                          zh: '每一帧都告诉你对上了没有、对不上是为什么',
                          en: 'Every frame tells you whether it lined up — and why it did not',
                        ),
                        style: text.bodySmall?.copyWith(
                            color: AstroColors.silver.withValues(alpha: 0.78), height: 1.35),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          CountUpText(count,
                              ms: 900,
                              style: text.headlineMedium?.copyWith(color: AstroColors.aligned)),
                          Text(tr(zh: '叠已完成', en: 'stacks made'),
                              style: text.labelSmall?.copyWith(
                                  color: AstroColors.silver.withValues(alpha: 0.7))),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.icon,
    required this.titleZh,
    required this.titleEn,
    required this.bodyZh,
    required this.bodyEn,
  });
  final int index;
  final IconData icon;
  final String titleZh;
  final String titleEn;
  final String bodyZh;
  final String bodyEn;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 21, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$index · ${tr(zh: titleZh, en: titleEn)}', style: text.titleSmall),
                const SizedBox(height: 3),
                Text(tr(zh: bodyZh, en: bodyEn),
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
