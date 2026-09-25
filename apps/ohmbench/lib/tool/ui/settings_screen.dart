import 'package:flutter/material.dart';

import '../../bench/identity.dart';
import '../../bench/words.dart';
import '../../bench/checkout.dart';
import '../pro.dart';
import '../store.dart';
import 'brand.dart';
import 'haptics.dart';
import 'lab_theme.dart';

/// OhmBench's own settings page: grouped, ruled rows on the bench (the iOS
/// settings shape), the mark at the top, the Pro module, then the small print.
class OhmSettingsScreen extends StatelessWidget {
  const OhmSettingsScreen({super.key, required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '实验台设置', en: 'Bench settings'))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
              BenchSpace.l, BenchSpace.l, BenchSpace.l, BenchSpace.xl),
          children: [
            const _Header(),
            const SizedBox(height: BenchSpace.l),
            _ProModule(store: store),
            const SizedBox(height: BenchSpace.xl),
            _SectionLabel(tr(zh: '这台设备', en: 'This device')),
            _Panel(children: [
              _Row(
                icon: Icons.memory_rounded,
                title: tr(zh: '保存的电路', en: 'Saved circuits'),
                trailing: Text(
                  '${store.projects.length}',
                  style: BenchType.monoStyle(BenchType.body, bold: true),
                ),
              ),
              _Row(
                icon: Icons.wifi_off_rounded,
                title: tr(zh: '网络权限', en: 'Network permission'),
                trailing: Text(tr(zh: '无', en: 'None'),
                    style: const TextStyle(color: Bench.inkDim)),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: BenchHaptics.enabled,
                builder: (context, on, _) => _Row(
                  icon: Icons.vibration_rounded,
                  title: tr(zh: '触感反馈', en: 'Haptics'),
                  subtitle: tr(
                      zh: '运行、放置元件、连线时轻震一下',
                      en: 'A light tap when you run, place a part or wire'),
                  trailing: Semantics(
                    label: tr(zh: '触感反馈', en: 'Haptics'),
                    child: Switch.adaptive(
                      value: on,
                      onChanged: (v) {
                        BenchHaptics.setEnabled(v);
                        BenchHaptics.select();
                      },
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: BenchLanguage.override,
                builder: (context, code, _) => _Row(
                  icon: Icons.translate_rounded,
                  title: tr(zh: '语言', en: 'Language'),
                  trailing: Text(BenchLanguage.label(code),
                      style: const TextStyle(color: Bench.inkDim)),
                  onTap: () => _pickLanguage(context, code),
                ),
              ),
            ]),
            const SizedBox(height: BenchSpace.xl),
            _SectionLabel(tr(zh: '说明', en: 'Small print')),
            _Panel(children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                title: tr(zh: '隐私政策', en: 'Privacy policy'),
                onTap: () => _open(context, tr(zh: '隐私政策', en: 'Privacy policy'),
                    OhmIdentity.privacyPolicy),
              ),
              _Row(
                icon: Icons.functions_rounded,
                title: tr(zh: '引擎与致谢', en: 'Engine & credits'),
                onTap: () => _open(context, tr(zh: '引擎与致谢', en: 'Engine & credits'),
                    _credits(),
                    licences: true),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static String _credits() => tr(
        zh: '求解器:改进节点法(MNA)+ 牛顿迭代 + 梯形积分,收敛容差沿用 SPICE 默认值(RELTOL 1e-3、VNTOL 1µV、ABSTOL 1pA)。\n\n'
            '结点限压、gmin 阶梯与源阶梯算法移植自 SpiceSharp(MIT 许可),© 2017 svenboulanger。\n\n'
            '触屏交互的抓取半径与拖动阈值参考了开源桌面电路仿真器的交互参数(仅参考行为,未使用其代码)。\n\n'
            '${OhmIdentity.appName} ${OhmIdentity.version}',
        en: 'Solver: modified nodal analysis with Newton iteration and trapezoidal integration, using SPICE default tolerances (RELTOL 1e-3, VNTOL 1 µV, ABSTOL 1 pA).\n\n'
            'Junction limiting and the gmin/source stepping ladder are ported from SpiceSharp (MIT licence), © 2017 svenboulanger.\n\n'
            'Touch grab radius and drag threshold follow the interaction parameters of an open-source desktop circuit simulator (behaviour only; none of its code is used).\n\n'
            '${OhmIdentity.appName} ${OhmIdentity.version}',
      );

  void _open(BuildContext context, String title, String body,
      {bool licences = false}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              BenchSpace.xl, BenchSpace.s, BenchSpace.xl, BenchSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(body, style: BenchType.bodyStyle(height: 1.6)),
              if (licences) ...[
                const SizedBox(height: BenchSpace.l),
                _Panel(children: [
                  _Row(
                    icon: Icons.description_outlined,
                    title: tr(zh: '开源许可', en: 'Open-source licences'),
                    onTap: () => showLicensePage(
                      context: ctx,
                      applicationName: OhmIdentity.appName,
                      applicationVersion: OhmIdentity.version,
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _pickLanguage(BuildContext context, String? current) async {
    const system = '_system';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in <String?>[null, ...BenchLanguage.choices])
              ListTile(
                leading: Icon(
                  c == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: c == current ? Bench.charge : Bench.inkDim,
                ),
                title: Text(BenchLanguage.label(c)),
                onTap: () => Navigator.pop(ctx, c ?? system),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await BenchLanguage.set(chosen == system ? null : chosen);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${OhmIdentity.appName} ${OhmIdentity.version}',
      excludeSemantics: true,
      child: Row(
        children: [
          const OhmMark(size: 28),
          const SizedBox(width: BenchSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OhmWordmark(),
                const SizedBox(height: BenchSpace.xs),
                Text(
                  tr(
                      zh: '离线电路仿真 · 版本 ${OhmIdentity.version}',
                      en: 'Offline circuit simulator · v${OhmIdentity.version}'),
                  style: BenchType.monoStyle(BenchType.label,
                      color: Bench.inkDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProModule extends StatelessWidget {
  const _ProModule({required this.store});

  final ProjectStore store;

  @override
  Widget build(BuildContext context) {
    if (store.pro) {
      return _Panel(children: [
        _Row(
          icon: Icons.bolt_rounded,
          iconColor: Bench.charge,
          title: tr(zh: 'Pro 已解锁', en: 'Pro unlocked'),
          subtitle: tr(
              zh: '不限元件、不限电路,谢谢支持',
              en: 'Unlimited parts and circuits. Thank you.'),
        ),
      ]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Bench.panel,
        borderRadius: BenchRadius.smAll,
        border: Border.all(color: Bench.charge),
      ),
      padding: const EdgeInsets.fromLTRB(
          BenchSpace.l, BenchSpace.l, BenchSpace.m, BenchSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: BenchSpace.m,
            runSpacing: BenchSpace.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(tr(zh: '解锁 Pro(一次买断)', en: 'Unlock Pro (one-time)'),
                  style: BenchType.bodyStyle(
                      size: BenchType.title, weight: FontWeight.w700)),
              FilledButton(
                onPressed: () => showProSheet(context),
                child: const StorePrice(fallback: r'$4.99'),
              ),
            ],
          ),
          const SizedBox(height: BenchSpace.s),
          Text(
            tr(
              zh: '免费版:1 张电路、每张 12 个元件。Pro 解除两个上限,引擎和精度完全相同。',
              en: 'Free: one circuit, twelve parts each. Pro lifts both limits; the engine and accuracy are the same.',
            ),
            style: BenchType.bodyStyle(color: Bench.inkDim),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => BenchCheckout.instance.restore(),
              child: Text(tr(zh: '恢复购买', en: 'Restore purchase')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(BenchSpace.xs, 0, 0, BenchSpace.s),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Bench.panel,
        borderRadius: BenchRadius.smAll,
        border: Border.all(color: Bench.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor = Bench.inkDim,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: BenchSpace.l, vertical: BenchSpace.m),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, color: iconColor, size: 20)),
          const SizedBox(width: BenchSpace.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BenchType.bodyStyle(size: BenchType.title)),
                if (subtitle != null) ...[
                  const SizedBox(height: BenchSpace.xs),
                  Text(subtitle!,
                      style: BenchType.bodyStyle(
                          color: Bench.inkDim, size: BenchType.label)),
                ],
              ],
            ),
          ),
          ?trailing,
          if (onTap != null && trailing == null)
            const ExcludeSemantics(
              child: Icon(Icons.chevron_right_rounded, color: Bench.inkDim),
            ),
        ],
      ),
    );
    if (onTap == null) {
      return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BenchSpace.row),
          child: row);
    }
    return Pressable(onTap: onTap, child: row);
  }
}
