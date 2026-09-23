import 'package:flutter/material.dart';

import '../../bench/identity.dart';
import '../../bench/words.dart';
import '../../bench/checkout.dart';
import '../pro.dart';
import '../store.dart';
import 'brand.dart';
import 'lab_theme.dart';

/// OhmBench's own settings page, laid out as a bench panel rather than the
/// shared template list: an instrument header, the Pro module, then the
/// small print.
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            const _Header(),
            const SizedBox(height: 16),
            _ProModule(store: store),
            const SizedBox(height: 22),
            _SectionLabel(tr(zh: '这台设备', en: 'This device')),
            _Panel(children: [
              _Row(
                icon: Icons.memory_rounded,
                title: tr(zh: '保存的电路', en: 'Saved circuits'),
                trailing: Text(
                  '${store.projects.length}',
                  style: const TextStyle(
                      color: Bench.positive,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              _Row(
                icon: Icons.wifi_off_rounded,
                title: tr(zh: '网络权限', en: 'Network permission'),
                trailing: Text(tr(zh: '无', en: 'None'),
                    style: const TextStyle(color: Bench.inkDim)),
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
            const SizedBox(height: 22),
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
                    _credits()),
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
            '触屏交互的抓取半径与拖动阈值参考了 circuitjs1 的交互规格(仅参考行为,未使用其代码)。\n\n'
            '${OhmIdentity.appName} ${OhmIdentity.version}',
        en: 'Solver: modified nodal analysis with Newton iteration and trapezoidal integration, using SPICE default tolerances (RELTOL 1e-3, VNTOL 1 µV, ABSTOL 1 pA).\n\n'
            'Junction limiting and the gmin/source stepping ladder are ported from SpiceSharp (MIT licence), © 2017 svenboulanger.\n\n'
            'Touch grab radius and drag threshold follow the interaction behaviour of circuitjs1 (behaviour only; none of its code is used).\n\n'
            '${OhmIdentity.appName} ${OhmIdentity.version}',
      );

  void _open(BuildContext context, String title, String body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Text(body,
              style: const TextStyle(color: Bench.ink, fontSize: 15, height: 1.6)),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 132,
        decoration: BoxDecoration(
          border: Border.all(color: Bench.panelBorder),
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10212C), Bench.background],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: Opacity(opacity: 0.7, child: ChargeField(count: 8))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const OhmMark(size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const OhmWordmark(size: 24),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                              zh: '离线电路仿真 · 版本 ${OhmIdentity.version}',
                              en: 'Offline circuit simulator · v${OhmIdentity.version}'),
                          style: const TextStyle(color: Bench.inkDim, fontSize: 13),
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
          subtitle: tr(zh: '不限元件 · 不限电路 · 谢谢支持', en: 'Unlimited parts and circuits · thank you'),
        ),
      ]);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Bench.charge.withValues(alpha: 0.45)),
        gradient: LinearGradient(
          colors: [Bench.charge.withValues(alpha: 0.12), Bench.panel],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Bench.charge),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(zh: '解锁 Pro(一次买断)', en: 'Unlock Pro (one-time)'),
                    style: const TextStyle(
                        color: Bench.ink, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                onPressed: () => showProSheet(context),
                child: const StorePrice(fallback: r'$4.99'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              zh: '免费版:1 张电路、每张 12 个元件。Pro 解除两个上限,引擎和精度完全相同。',
              en: 'Free: one circuit, twelve parts each. Pro lifts both limits; the engine and accuracy are the same.',
            ),
            style: const TextStyle(color: Bench.inkDim, fontSize: 13, height: 1.4),
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
        padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: Bench.inkDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Bench.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
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
    this.iconColor = Bench.positive,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: Bench.ink, fontSize: 15.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(color: Bench.inkDim, fontSize: 13)),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (onTap != null && trailing == null)
              const Icon(Icons.chevron_right_rounded, color: Bench.inkDim),
          ],
        ),
      ),
    );
  }
}
