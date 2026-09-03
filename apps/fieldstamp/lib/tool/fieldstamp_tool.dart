import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'models.dart';
import 'pro.dart';
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
        // Renders nothing; surfaces store errors/pending/unlocked as snackbars.
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(store.pro ? Icons.verified : Icons.lock_open_outlined),
            title: Text(store.pro
                ? tr(zh: '已解锁 Pro', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: Text(store.pro
                ? tr(zh: '感谢你的支持', en: 'Thanks for your support')
                : tr(
                    zh: '一次买断:多项目、PDF/CSV 导出、度分秒坐标、去除水印角标',
                    en: 'One-time purchase: multiple projects, PDF/CSV export, '
                        'DMS coordinates, no watermark tag')),
            trailing: store.pro
                ? null
                : FilledButton.tonal(
                    onPressed: () => _confirmUnlock(context),
                    child: const ProPriceText(fallback: r'$6.99'),
                  ),
            onTap: store.pro ? null : () => _confirmUnlock(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: Text(tr(zh: '坐标格式', en: 'Coordinate format')),
            subtitle: Text(store.coordFormat == CoordFormat.decimal
                ? tr(zh: '十进制度', en: 'Decimal degrees')
                : tr(
                    zh: '度 / 分 / 秒(Pro)',
                    en: 'Degrees / minutes / seconds (Pro)')),
            onTap: () => _pickCoordFormat(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.height),
            title: Text(tr(zh: '海拔单位', en: 'Altitude unit')),
            subtitle: Text(store.altUnit == AltUnit.meters
                ? tr(zh: '米', en: 'Meters')
                : tr(zh: '英尺', en: 'Feet')),
            onTap: () => store.setAltUnit(
                store.altUnit == AltUnit.meters ? AltUnit.feet : AltUnit.meters),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(tr(zh: '项目', en: 'Projects')),
            subtitle: Text(tr(
                zh: '${store.projects.length} 个项目',
                en: '${store.projects.length} project(s)')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProjectsPage(store: store),
            )),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr(zh: '水印是如何烧入的', en: 'How stamping works')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _HowItWorksPage(),
          )),
        ),
      ];

  void _confirmUnlock(BuildContext context) => showProSheet(context);

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
              title: Text(tr(zh: '十进制度', en: 'Decimal degrees')),
              subtitle: Text(
                  tr(zh: '例如:37.774900, -122.419400', en: 'e.g. 37.774900, -122.419400')),
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
                  ? tr(zh: '度 / 分 / 秒', en: 'Degrees / minutes / seconds')
                  : tr(
                      zh: '度 / 分 / 秒(Pro)',
                      en: 'Degrees / minutes / seconds (Pro)')),
              subtitle: Text(tr(
                  zh: "例如:37°46'29.6\"N  122°25'09.8\"W",
                  en: "e.g. 37°46'29.6\"N  122°25'09.8\"W")),
              onTap: () {
                if (!store.pro) {
                  Navigator.pop(ctx);
                  showProSheet(context,
                      reason: tr(
                          zh: '度 / 分 / 秒坐标格式是 Pro 功能。',
                          en: 'DMS coordinates are a Pro feature.'));
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
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.camera_alt_outlined),
              selectedIcon: const Icon(Icons.camera_alt),
              label: tr(zh: '相机', en: 'Camera')),
          NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library),
              label: tr(zh: '相册', en: 'Gallery')),
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
      appBar: AppBar(title: Text(tr(zh: '项目', en: 'Projects'))),
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
                subtitle: Text(tr(
                    zh: '${store.photosForProject(p.id).length} 张照片',
                    en: '${store.photosForProject(p.id).length} photos')),
                onTap: () => store.selectProject(p.id),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final name = await _prompt(context,
                          tr(zh: '重命名项目', en: 'Rename project'), p.name);
                      if (name != null && name.trim().isNotEmpty) {
                        store.renameProject(p, name);
                      }
                    } else if (v == 'delete') {
                      if (store.projects.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(tr(
                                zh: '至少保留一个项目。',
                                en: 'Keep at least one project.'))));
                        return;
                      }
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr(
                              zh: '删除「${p.name}」?',
                              en: 'Delete "${p.name}"?')),
                          content: Text(tr(
                              zh: '将删除该项目及其 '
                                  '${store.photosForProject(p.id).length} 张照片。',
                              en: 'Deletes the project and its '
                                  '${store.photosForProject(p.id).length} photos.')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(tr(zh: '取消', en: 'Cancel'))),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(tr(zh: '删除', en: 'Delete')),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await store.deleteProject(p);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'rename',
                        child: Text(tr(zh: '重命名', en: 'Rename'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text(tr(zh: '删除', en: 'Delete'))),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!store.pro) {
            showProSheet(context,
                reason: tr(
                    zh: '免费版只有一个项目,多项目 / 工单是 Pro 功能。',
                    en: 'The free tier has one project; multiple projects are a Pro feature.'));
            return;
          }
          final name =
              await _prompt(context, tr(zh: '新建项目', en: 'New project'), '');
          if (name != null && name.trim().isNotEmpty) {
            store.addProject(name);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(tr(zh: '新建项目', en: 'New project')),
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
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(zh: '取消', en: 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr(zh: '确定', en: 'OK'))),
        ],
      ),
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final body = tr(
      zh: '''
FieldStamp 把每张照片都变成一份小小的现场证据。

按下快门时,应用会读取设备的 GPS(经纬度、海拔和精度)、磁力计方位和当前时间,连同项目名一起直接烧入照片的像素里。因为水印是在拍摄瞬间合成的(不是事后叠加),照片本身就承载着这份记录。

这些数值也会随每张照片一起保存,之后可以导出 PDF 巡检报告或 CSV 台账。

拍出好水印的小技巧:
• 在户外给 GPS 几秒钟时间,让精度(显示为 ±米)达到理想值。
• 如果方位看起来不对,把手机按"8"字形晃动以校准罗盘。
• 海拔来自 GPS,可能有波动,仅供参考。

隐私:一切都在本机完成。FieldStamp 不申请网络权限——你的照片和坐标永远不会离开你的手机。
''',
      en: '''
FieldStamp turns every photo into a small piece of field evidence.

When you tap the shutter, the app reads your device's GPS (latitude, longitude, altitude and accuracy), the magnetometer bearing, and the current time — then burns them, together with the project name, directly into the photo's pixels. Because the stamp is composited at the moment of capture (not added afterward), the image itself carries the record.

The same values are also saved alongside each photo so you can export a PDF inspection report or a CSV ledger later.

Tips for good stamps:
• Give the GPS a few seconds outdoors to reach good accuracy (shown as ±metres).
• Move the phone in a figure-8 to calibrate the compass if the bearing looks off.
• Altitude comes from GPS and can vary; treat it as approximate.

Privacy: everything happens on this device. FieldStamp requests no network permission — your photos and coordinates never leave your phone.
''',
    );
    return Scaffold(
      appBar: AppBar(
          title: Text(tr(zh: '水印是如何烧入的', en: 'How stamping works'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body, style: const TextStyle(height: 1.5)),
      ),
    );
  }
}
