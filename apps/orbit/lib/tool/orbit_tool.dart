import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'align_screen.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'import_screen.dart';
import 'models.dart';
import 'pro.dart';
import 'sensors.dart';
import 'site_screen.dart';
import 'store.dart';
import 'tool_module.dart';

/// Orbit: satellite pass predictions computed entirely on the device.
///
/// SGP4 propagation, sun geometry and the visibility verdict are all local
/// maths; GPS and the magnetometer are local sensors; the element sets ship in
/// the package and are refreshed by paste. The app declares no INTERNET
/// permission, so the privacy claim is verifiable from the manifest.
class OrbitTool implements ToolModule {
  OrbitTool() {
    store.load();
  }

  final OrbitStore store = OrbitStore();
  final SensorHub sensors = SensorHub();

  @override
  Widget buildHome(BuildContext context) => _Home(store: store, sensors: sensors);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.workspace_premium : Icons.lock_open),
            title: Text(store.pro
                ? tr(zh: 'Orbit Pro —— 已解锁', en: 'Orbit Pro — unlocked')
                : tr(zh: '解锁 Orbit Pro', en: 'Unlock Orbit Pro')),
            subtitle: Text(store.pro
                ? tr(
                    zh: '全部目标、10 天预报、自定义轨道数据',
                    en: 'Every target, 10-day forecast, custom element sets')
                : tr(
                    zh: '全部 ${store.catalog.length} 个目标 + 10 天预报',
                    en: 'All ${store.catalog.length} targets + a 10-day forecast')),
            onTap: store.pro ? null : () => showProSheet(context, store),
          ),
        ),
      ];
}

class _Home extends StatefulWidget {
  const _Home({required this.store, required this.sensors});

  final OrbitStore store;
  final SensorHub sensors;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A forecast is a window starting at the instant it was computed. Left
    // alone for a few days, a two-day forecast is nothing but passes that
    // already happened — and the hero would cheerfully announce "a quiet few
    // nights overhead" because it found nothing in the future.
    if (state == AppLifecycleState.resumed &&
        widget.store.hasSite &&
        widget.store.forecastIsStale &&
        !widget.store.searching) {
      unawaited(widget.store.refresh());
    }
  }

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImportScreen(store: widget.store)),
    );
  }

  void _openAlign(SatPass pass) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlignScreen(
          pass: pass,
          store: widget.store,
          sensors: widget.sensors,
        ),
      ),
    );
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
          HomeScreen(
            store: widget.store,
            onNeedSite: () => setState(() => _tab = 2),
            onNeedUpdate: _openImport,
            onAlign: _openAlign,
          ),
          CatalogScreen(store: widget.store, onImport: _openImport),
          SiteScreen(store: widget.store),
        ];
        return Scaffold(
          body: IndexedStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.schedule_outlined),
                selectedIcon: const Icon(Icons.schedule),
                label: tr(zh: '过境', en: 'Passes'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.satellite_alt_outlined),
                selectedIcon: const Icon(Icons.satellite_alt),
                label: tr(zh: '目标', en: 'Targets'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.place_outlined),
                selectedIcon: const Icon(Icons.place),
                label: tr(zh: '观测点', en: 'Site'),
              ),
            ],
          ),
        );
      },
    );
  }
}
