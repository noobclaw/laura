import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'location_store.dart';
import 'sensors.dart';
import 'light_view.dart';
import 'planner_screen.dart';
import 'location_screen.dart';
import 'pro.dart';
import 'tool_module.dart';

/// GoldenScout: an offline photography light planner. Sun/Moon almanac is pure
/// device-side math; GPS + magnetometer are local sensors; nothing is uploaded.
class GoldenscoutTool implements ToolModule {
  GoldenscoutTool() {
    store.load();
  }

  final LocationStore store = LocationStore();
  final SensorHub sensors = SensorHub();

  @override
  Widget buildHome(BuildContext context) => _Home(store: store, sensors: sensors);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        // Renders nothing; surfaces store errors/pending/unlocked as snackbars.
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.workspace_premium : Icons.lock_open),
            title: Text(store.pro
                ? tr(zh: 'GoldenScout Pro——已解锁', en: 'GoldenScout Pro — unlocked')
                : tr(zh: '解锁 GoldenScout Pro', en: 'Unlock GoldenScout Pro')),
            subtitle: Text(store.pro
                ? tr(
                    zh: '任意日期、无限机位、完整月亮详情',
                    en: 'Any date, unlimited saved spots, moon details')
                : tr(
                    zh: '规划任意日期 + 保存无限拍摄机位',
                    en: 'Plan any date + save unlimited shooting spots')),
            onTap: store.pro ? null : () => showProSheet(context, store),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
      ];
}

class _Home extends StatefulWidget {
  const _Home({required this.store, required this.sensors});
  final LocationStore store;
  final SensorHub sensors;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.sensors.startCompass();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (!widget.store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final pages = [
          LightView(
            store: widget.store,
            sensors: widget.sensors,
            date: _todayDate(),
            isToday: true,
            onNeedLocation: () => setState(() => _tab = 2),
          ),
          PlannerScreen(
            store: widget.store,
            sensors: widget.sensors,
            onNeedLocation: () => setState(() => _tab = 2),
          ),
          LocationScreen(store: widget.store),
        ];
        return Scaffold(
          body: IndexedStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.wb_sunny_outlined),
                  selectedIcon: const Icon(Icons.wb_sunny),
                  label: tr(zh: '今日', en: 'Today')),
              NavigationDestination(
                  icon: const Icon(Icons.event_outlined),
                  selectedIcon: const Icon(Icons.event),
                  label: tr(zh: '规划', en: 'Planner')),
              NavigationDestination(
                  icon: const Icon(Icons.place_outlined),
                  selectedIcon: const Icon(Icons.place),
                  label: tr(zh: '机位', en: 'Location')),
            ],
          ),
        );
      },
    );
  }

  DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
}
