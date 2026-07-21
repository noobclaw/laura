import 'package:flutter/material.dart';

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
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.workspace_premium : Icons.lock_open),
            title: Text(store.pro ? 'GoldenScout Pro — unlocked' : 'Unlock GoldenScout Pro'),
            subtitle: Text(store.pro
                ? 'Any date, unlimited saved spots, moon details'
                : 'Plan any date + save unlimited shooting spots'),
            onTap: store.pro ? null : () => showProSheet(context, store),
          ),
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
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  selectedIcon: Icon(Icons.wb_sunny),
                  label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.event_outlined),
                  selectedIcon: Icon(Icons.event),
                  label: 'Planner'),
              NavigationDestination(
                  icon: Icon(Icons.place_outlined),
                  selectedIcon: Icon(Icons.place),
                  label: 'Location'),
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
