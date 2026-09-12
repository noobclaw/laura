import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';
import 'engine/output.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'ui/compress_screen.dart';
import 'ui/convert_screen.dart';
import 'ui/crop_screen.dart';
import 'ui/metadata_screen.dart';
import 'ui/resize_screen.dart';
import 'ui/tool_board.dart';
import 'ui/watermark_screen.dart';
import 'ui/widgets.dart';

/// The image toolbox: the six-tile tool board is the home screen's hero and
/// its navigation; Pro rows live in Settings. Everything else lives behind
/// the tool screens.
class PicboxTool extends ToolModule {
  PicboxTool();

  final PicboxStore store = PicboxStore();

  @override
  Widget buildHome(BuildContext context) => _Home(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(Icons.workspace_premium, color: Theme.of(context).colorScheme.primary),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: store.pro
                ? Text(tr(zh: '不限张数 · WebP · 预设 · 记住设置', en: 'Unlimited batch · WebP · presets · saved settings'))
                : Text(tr(
                    zh: '不限张数 · WebP · 预设 · 记住设置 · 一次买断',
                    en: 'Unlimited batch · WebP · presets · saved settings · one-time')),
            trailing: store.pro
                ? null
                : FilledButton.tonal(
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
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(tr(zh: '清理临时文件', en: 'Clear temporary files')),
          subtitle: Text(tr(zh: '删除处理过程中产生的缓存', en: 'Remove caches from previous runs')),
          onTap: () async {
            await WorkDirs.clearAll();
            if (context.mounted) showNotice(context, tr(zh: '已清理', en: 'Cleared'));
          },
        ),
      ];
}

class _Home extends StatefulWidget {
  const _Home({required this.store});
  final PicboxStore store;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    // Leftovers from a run that was interrupted (crash, force-quit).
    WorkDirs.clearAll();
  }

  void _open(ToolKind k) {
    final s = widget.store;
    final Widget page = switch (k) {
      ToolKind.compress => CompressScreen(store: s),
      ToolKind.resize => ResizeScreen(store: s),
      ToolKind.convert => ConvertScreen(store: s),
      ToolKind.crop => CropScreen(store: s),
      ToolKind.metadata => MetadataScreen(store: s),
      ToolKind.watermark => WatermarkScreen(store: s),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Masthead(pro: widget.store.pro),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Text(tr(zh: '工具', en: 'Tools'),
                    style: text.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text(
                  tr(zh: '点一格开始', en: 'Tap a tile to start'),
                  style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ToolBoard(onOpen: _open),
          const SizedBox(height: 16),
          _Stats(count: widget.store.processedCount),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr(
                    zh: '无网络权限,图片只在这台手机上处理。',
                    en: 'No network permission — pictures are processed on this phone only.',
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

/// Title block above the board: name, one line of promise, the plan badge.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.pro});
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(zh: '六件图片小工具\n一次批量搞定', en: 'Six image tools,\none batch at a time'),
                  style: text.headlineSmall?.copyWith(height: 1.15, letterSpacing: -0.3),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(zh: '压缩 · 缩放 · 转格式 · 裁剪 · 去元数据 · 水印',
                      en: 'Compress · Resize · Convert · Crop · Clean · Watermark'),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: pro ? Branding.seedColor : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              pro ? 'PRO' : tr(zh: '离线 · 免费', en: 'OFFLINE · FREE'),
              style: text.labelSmall?.copyWith(
                color: pro ? Colors.white : cs.onSurfaceVariant,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "N pictures processed" — the number rolls up rather than jumping.
class _Stats extends StatelessWidget {
  const _Stats({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final lime = ToolColors.compress;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lime.withValues(alpha: 0.16),
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 18, color: lime),
          ),
          const SizedBox(width: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: count.toDouble()),
            duration: Motion.of(context, Motion.count),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              '${v.round()}',
              style: text.headlineSmall?.copyWith(color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == 0
                  ? tr(zh: '张已处理 · 从上面挑一件工具开始', en: 'processed · pick a tool above to start')
                  : tr(zh: '张已处理', en: 'pictures processed'),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
