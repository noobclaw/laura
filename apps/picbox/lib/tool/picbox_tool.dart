import 'package:flutter/material.dart';

import '../core/branding.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
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
import 'ui/watermark_screen.dart';
import 'ui/widgets.dart';

/// The image toolbox: a hero + six-tool grid on the home screen, Pro rows
/// in Settings. Everything else lives behind the tool screens.
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
                : Row(
                    children: [
                      Text(tr(zh: '一次买断 ', en: 'One-time purchase ')),
                      const ProPriceText(fallback: kProFallbackPrice),
                    ],
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
          _Hero(count: widget.store.processedCount, pro: widget.store.pro),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(tr(zh: '工具', en: 'Tools'),
                style: text.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.18,
            children: [
              for (final k in ToolKind.values) _ToolCard(meta: ToolMeta.of(k), onTap: () => _open(k)),
            ],
          ),
          const SizedBox(height: 20),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.count, required this.pro});
  final int count;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seed = Branding.seedColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [seed, const Color(0xFF145C7A)],
        ),
        boxShadow: [BoxShadow(color: seed.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -22,
            child: Icon(Icons.layers_rounded, size: 140, color: Colors.white.withValues(alpha: 0.10)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      pro ? 'PRO' : tr(zh: '离线 · 免费', en: 'OFFLINE · FREE'),
                      style: text.labelSmall?.copyWith(color: Colors.white, letterSpacing: 1, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr(zh: '六件图片小工具\n一次批量搞定', en: 'Six image tools,\none batch at a time'),
                style: text.headlineSmall?.copyWith(color: Colors.white, height: 1.2),
              ),
              const SizedBox(height: 8),
              Text(
                tr(zh: '压缩 · 缩放 · 转格式 · 裁剪 · 去元数据 · 水印', en: 'Compress · Resize · Convert · Crop · Clean · Watermark'),
                style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              if (count > 0) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$count', style: text.headlineMedium?.copyWith(color: Colors.white)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(tr(zh: '张已处理', en: 'pictures processed'),
                          style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.meta, required this.onTap});
  final ToolMeta meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: meta.color.withValues(alpha: 0.14),
                ),
                child: Icon(meta.icon, color: meta.color, size: 22),
              ),
              const Spacer(),
              Text(meta.title, style: text.titleMedium),
              const SizedBox(height: 3),
              // Reserve two lines so titles line up across the grid whether the
              // subtitle wraps or not (smoke screenshot showed Watermark sitting
              // lower than Strip Metadata).
              SizedBox(
                height: (text.bodySmall?.fontSize ?? 12) * 1.25 * 2 + 2,
                child: Text(
                  meta.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
