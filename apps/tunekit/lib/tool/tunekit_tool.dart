import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'app_theme.dart';
import 'log_page.dart';
import 'metronome_controller.dart';
import 'metronome_page.dart';
import 'mic_controller.dart';
import 'practice_page.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'tuner_page.dart';

/// TuneBench: tuner + metronome + chord/scale practice + practice log.
class TuneKitTool extends ToolModule {
  TuneKitTool();

  final TuneKitStore store = TuneKitStore();
  late final MicPitchController mic = MicPitchController(store);
  late final MetronomeController metro = MetronomeController(store);

  /// Selected bottom tab; the app bar title follows it.
  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  String tabTitle(int i) => switch (i) {
        0 => tr(zh: '调音器', en: 'Tuner'),
        1 => tr(zh: '节拍器', en: 'Metronome'),
        2 => tr(zh: '和弦与音阶', en: 'Chords & scales'),
        _ => tr(zh: '练习记录', en: 'Practice log'),
      };

  @override
  Widget buildHome(BuildContext context) => _TuneHome(tool: this);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.workspace_premium, color: kBeatAmber),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: store.pro
                ? Text(tr(zh: '全部预设、拍号、字典与记录已开启', en: 'All presets, metres, dictionary and history are on'))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(zh: '一次性买断 ', en: 'One-time purchase · ')),
                      const ProPriceText(fallback: '\$3.99'),
                    ],
                  ),
            onTap: store.pro ? null : () => showProSheet(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
      ];
}

class _TuneHome extends StatefulWidget {
  const _TuneHome({required this.tool});
  final TuneKitTool tool;

  @override
  State<_TuneHome> createState() => _TuneHomeState();
}

class _TuneHomeState extends State<_TuneHome> {
  @override
  void initState() {
    super.initState();
    widget.tool.tabIndex.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.tool.tabIndex.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final index = tool.tabIndex.value;
    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: index,
            children: [
              TunerPage(store: tool.store, mic: tool.mic, active: index == 0),
              MetronomePage(store: tool.store, metro: tool.metro),
              PracticePage(store: tool.store, mic: tool.mic),
              LogPage(store: tool.store),
            ],
          ),
        ),
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => tool.tabIndex.value = i,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.graphic_eq_outlined),
              selectedIcon: const Icon(Icons.graphic_eq),
              label: tr(zh: '调音', en: 'Tune'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.timer_outlined),
              selectedIcon: const Icon(Icons.timer),
              label: tr(zh: '节拍', en: 'Beat'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.piano_outlined),
              selectedIcon: const Icon(Icons.piano),
              label: tr(zh: '练习', en: 'Practice'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: tr(zh: '记录', en: 'Log'),
            ),
          ],
        ),
      ],
    );
  }
}
