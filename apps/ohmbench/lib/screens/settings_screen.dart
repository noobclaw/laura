import 'package:flutter/material.dart';

import '../app/app_info.dart';
import '../app/unlock_ui.dart';
import '../i18n/lang.dart';
import '../i18n/txt.dart';
import '../platform/unlock_service.dart';
import '../workshop/pro.dart';
import '../workshop/store.dart';
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
      appBar: AppBar(title: Text(Txt.benchSettings)),
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
            _SectionLabel(Txt.device),
            _Panel(children: [
              _Row(
                icon: Icons.memory_rounded,
                title: Txt.savedCircuits,
                trailing: Text(
                  '${store.projects.length}',
                  style: BenchType.monoStyle(BenchType.body, bold: true),
                ),
              ),
              _Row(
                icon: Icons.wifi_off_rounded,
                title: Txt.networkPermission,
                trailing: Text(Txt.none,
                    style: const TextStyle(color: Bench.inkDim)),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: BenchHaptics.enabled,
                builder: (context, on, _) => _Row(
                  icon: Icons.vibration_rounded,
                  title: Txt.haptics,
                  subtitle: Txt.lightTapWhenRun,
                  trailing: Semantics(
                    label: Txt.haptics,
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
                valueListenable: Lang.picked,
                builder: (context, code, _) => _Row(
                  icon: Icons.translate_rounded,
                  title: Txt.language,
                  trailing: Text(code == null ? Txt.followSystem : Lang.nativeName(code),
                      style: const TextStyle(color: Bench.inkDim)),
                  onTap: () => _pickLanguage(context, code),
                ),
              ),
            ]),
            const SizedBox(height: BenchSpace.xl),
            _SectionLabel(Txt.smallPrint),
            _Panel(children: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                title: Txt.privacyPolicy,
                onTap: () => _open(context, Txt.privacyPolicy,
                    AppInfo.privacyPolicy),
              ),
              _Row(
                icon: Icons.functions_rounded,
                title: Txt.engineCredits,
                onTap: () => _open(context, Txt.engineCredits,
                    _credits(),
                    licences: true),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static String _credits() => Txt.solverModifiedNodalAnalysis(AppInfo.name, AppInfo.version);

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
                    title: Txt.openSourceLicences,
                    onTap: () => showLicensePage(
                      context: ctx,
                      applicationName: AppInfo.name,
                      applicationVersion: AppInfo.version,
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
            for (final c in <String?>[null, ...Lang.supported])
              ListTile(
                leading: Icon(
                  c == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: c == current ? Bench.charge : Bench.inkDim,
                ),
                title: Text(c == null ? Txt.followSystem : Lang.nativeName(c)),
                onTap: () => Navigator.pop(ctx, c ?? system),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    Lang.pick(chosen == system ? null : chosen);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${AppInfo.name} ${AppInfo.version}',
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
                  Txt.offlineCircuitSimulatorV(AppInfo.version),
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
          title: Txt.proUnlocked,
          subtitle: Txt.unlimitedPartsCircuitsThank,
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
              Text(Txt.unlockProOneTime,
                  style: BenchType.bodyStyle(
                      size: BenchType.title, weight: FontWeight.w700)),
              FilledButton(
                onPressed: () => showProSheet(context),
                child: const PriceTag(fallback: r'$4.99'),
              ),
            ],
          ),
          const SizedBox(height: BenchSpace.s),
          Text(
            Txt.freeOneCircuitTwelve,
            style: BenchType.bodyStyle(color: Bench.inkDim),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => UnlockService.shared.restorePurchases(),
              child: Text(Txt.restorePurchase),
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
