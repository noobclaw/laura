import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/day_change.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'home_screen.dart';
import 'job_runner.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';

/// PhotoLift: on-device Real-ESRGAN upscaling for old photos.
class PhotoLiftTool extends ToolModule {
  PhotoLiftTool() {
    runner = LiftJobRunner(store);
    store.load();
    // The free allowance is per local day: re-render the quota card when the
    // day changes under an open app (midnight, or resume on a later day).
    _dayChange
      ..addListener(store.dayChanged)
      ..start();
  }

  final PhotoLiftStore store = PhotoLiftStore();
  late final LiftJobRunner runner;
  final DayChangeNotifier _dayChange = DayChangeNotifier();

  @override
  Widget buildHome(BuildContext context) => HomeScreen(store: store, runner: runner);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _ProTile(store: store),
        _GpuTile(store: store),
        _DenoiseTile(store: store),
        _LibraryTile(store: store),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.workspace_premium, color: cs.primary),
              title: Text(store.pro
                  ? tr(zh: 'PhotoLift Pro 已解锁', en: 'PhotoLift Pro unlocked')
                  : tr(zh: '升级 PhotoLift Pro', en: 'Upgrade to PhotoLift Pro')),
              subtitle: store.pro
                  ? Text(tr(zh: '不限张数 · 4x · 无标签', en: 'Unlimited · 4x · no tag'))
                  : Row(children: [
                      Expanded(
                          child: Text(tr(
                              zh: '不限张数、4x 放大、去标签 —— 一次买断 ',
                              en: 'Unlimited, 4x, no tag — one-time '))),
                      const ProPriceText(fallback: '\$6.99'),
                    ]),
              onTap: store.pro ? null : () => showProSheet(context),
            ),
            RestorePurchasesTile(pro: store.pro),
          ],
        );
      },
    );
  }
}

class _GpuTile extends StatelessWidget {
  const _GpuTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    // The iOS build of the engine is CPU-only (see PLAN.md), so the switch
    // would be a lie there; it is an Android-only setting, not a code path.
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SwitchListTile(
        secondary: const Icon(Icons.memory),
        title: Text(tr(zh: 'GPU 加速', en: 'GPU acceleration')),
        subtitle: Text(tr(
          zh: '用 Vulkan 跑模型,通常快 5-10 倍。出现花屏或失败时关闭。',
          en: 'Runs the model on Vulkan, usually 5-10x faster. Turn off if results look corrupted or fail.',
        )),
        value: store.useGpu,
        onChanged: store.setUseGpu,
      ),
    );
  }
}

class _DenoiseTile extends StatelessWidget {
  const _DenoiseTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListTile(
        leading: const Icon(Icons.blur_on),
        title: Text(tr(zh: '默认降噪', en: 'Default denoise')),
        subtitle: Text(store.defaultDenoise.label),
        onTap: () async {
          final picked = await showDialog<DenoiseLevel>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(tr(zh: '默认降噪', en: 'Default denoise')),
              children: [
                for (final d in DenoiseLevel.values)
                  RadioListTile<DenoiseLevel>(
                    value: d,
                    // ignore: deprecated_member_use
                    groupValue: store.defaultDenoise,
                    title: Text(d.label),
                    // ignore: deprecated_member_use
                    onChanged: (v) => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          );
          if (picked != null) store.setDefaultDenoise(picked);
        },
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => FutureBuilder<int>(
        future: store.libraryBytes(),
        builder: (context, snap) {
          final mb = (snap.data ?? 0) / (1024 * 1024);
          return ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr(zh: '清空修复记录', en: 'Clear history')),
            subtitle: Text(tr(
              zh: '${store.history.length} 张 · ${mb.toStringAsFixed(1)} MB(只删应用内副本,不动相册)',
              en: '${store.history.length} photos · ${mb.toStringAsFixed(1)} MB (in-app copies only, Photos untouched)',
            )),
            enabled: store.history.isNotEmpty,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr(zh: '清空修复记录?', en: 'Clear history?')),
                  content: Text(tr(
                    zh: '会删除应用内保存的全部原图副本和修复结果。已保存到相册的照片不受影响。',
                    en: 'Deletes every source copy and result kept inside the app. Photos already saved to your library are not affected.',
                  )),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr(zh: '取消', en: 'Cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr(zh: '清空', en: 'Clear'))),
                  ],
                ),
              );
              if (ok == true) await store.clearHistory();
            },
          );
        },
      ),
    );
  }
}
