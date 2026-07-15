import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'models.dart';
import 'sensors.dart';
import 'store.dart';
import 'tool_module.dart';

/// FieldStamp: an offline GPS field-evidence camera. Everything the shell needs
/// is behind [ToolModule]; the store and sensor hub are created once and shared.
class FieldStampTool extends ToolModule {
  FieldStampTool() {
    store.load();
  }

  final FieldStampStore store = FieldStampStore();
  final SensorHub sensors = SensorHub();

  @override
  Widget buildHome(BuildContext context) =>
      HomeShell(store: store, sensors: sensors);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.verified : Icons.lock_open_outlined),
            title: Text(store.pro ? 'Pro unlocked' : 'Unlock Pro'),
            subtitle: Text(store.pro
                ? 'Thanks for your support'
                : 'One-time purchase: multiple projects, PDF/CSV export, '
                    'DMS coordinates, no watermark tag'),
            onTap: store.pro ? null : () => _confirmUnlock(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('Coordinate format'),
            subtitle: Text(store.coordFormat == CoordFormat.decimal
                ? 'Decimal degrees'
                : 'Degrees / minutes / seconds (Pro)'),
            onTap: () => _pickCoordFormat(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.height),
            title: const Text('Altitude unit'),
            subtitle:
                Text(store.altUnit == AltUnit.meters ? 'Meters' : 'Feet'),
            onTap: () => store.setAltUnit(
                store.altUnit == AltUnit.meters ? AltUnit.feet : AltUnit.meters),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Projects'),
            subtitle: Text('${store.projects.length} project(s)'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProjectsPage(store: store),
            )),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('How stamping works'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _HowItWorksPage(),
          )),
        ),
      ];

  void _confirmUnlock(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlock Pro'),
        content: const Text(
          'A one-time purchase unlocks:\n'
          '• Multiple projects / work orders\n'
          '• PDF inspection reports & CSV ledgers\n'
          '• Degrees-minutes-seconds coordinates\n'
          '• Removes the small FieldStamp tag on photos\n\n'
          '(The store purchase is added before release; this is a local switch '
          'for now.)',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              store.unlockPro();
              Navigator.pop(ctx);
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _pickCoordFormat(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(store.coordFormat == CoordFormat.decimal
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: const Text('Decimal degrees'),
              subtitle: const Text('e.g. 37.774900, -122.419400'),
              onTap: () {
                store.setCoordFormat(CoordFormat.decimal);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(store.coordFormat == CoordFormat.dms
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(store.pro
                  ? 'Degrees / minutes / seconds'
                  : 'Degrees / minutes / seconds (Pro)'),
              subtitle: const Text("e.g. 37°46'29.6\"N  122°25'09.8\"W"),
              onTap: () {
                if (!store.pro) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('DMS coordinates are a Pro feature.'),
                  ));
                  return;
                }
                store.setCoordFormat(CoordFormat.dms);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabbed home: Camera + Gallery, sharing one store and sensor hub. Nested in
/// the shell scaffold (which supplies the app bar + settings button).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, required this.sensors});

  final FieldStampStore store;
  final SensorHub sensors;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.sensors.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CameraScreen(store: widget.store, sensors: widget.sensors),
          GalleryScreen(store: widget.store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt),
              label: 'Camera'),
          NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Gallery'),
        ],
      ),
    );
  }
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.store});

  final FieldStampStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          children: [
            for (final p in store.projects)
              ListTile(
                leading: Icon(p.id == store.currentProjectId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(p.name),
                subtitle: Text(
                    '${store.photosForProject(p.id).length} photos'),
                onTap: () => store.selectProject(p.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final name = await _prompt(context, 'Rename project', p.name);
                      if (name != null && name.trim().isNotEmpty) {
                        store.renameProject(p, name);
                      }
                    } else if (v == 'delete') {
                      if (store.projects.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Keep at least one project.')));
                        return;
                      }
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Delete "${p.name}"?'),
                          content: Text(
                              'Deletes the project and its '
                              '${store.photosForProject(p.id).length} photos.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await store.deleteProject(p);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!store.pro) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Multiple projects are a Pro feature. Unlock in Settings.'),
            ));
            return;
          }
          final name = await _prompt(context, 'New project', '');
          if (name != null && name.trim().isNotEmpty) {
            store.addProject(name);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('New project'),
      ),
    );
  }

  Future<String?> _prompt(BuildContext context, String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    const body = '''
FieldStamp turns every photo into a small piece of field evidence.

When you tap the shutter, the app reads your device's GPS (latitude, longitude, altitude and accuracy), the magnetometer bearing, and the current time — then burns them, together with the project name, directly into the photo's pixels. Because the stamp is composited at the moment of capture (not added afterward), the image itself carries the record.

The same values are also saved alongside each photo so you can export a PDF inspection report or a CSV ledger later.

Tips for good stamps:
• Give the GPS a few seconds outdoors to reach good accuracy (shown as ±metres).
• Move the phone in a figure-8 to calibrate the compass if the bearing looks off.
• Altitude comes from GPS and can vary; treat it as approximate.

Privacy: everything happens on this device. FieldStamp requests no network permission — your photos and coordinates never leave your phone.
''';
    return Scaffold(
      appBar: AppBar(title: const Text('How stamping works')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(body, style: TextStyle(height: 1.5)),
      ),
    );
  }
}
