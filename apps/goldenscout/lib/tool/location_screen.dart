import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'location_store.dart';
import 'models.dart';
import 'sensors.dart';
import 'pro.dart';

/// Location management: grab a live GPS fix, or add/select/delete saved
/// shooting spots. Saving more than one spot is a Pro feature.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.store});
  final LocationStore store;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  bool _locating = false;

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final fix = await SensorHub.currentFix();
      widget.store.useCurrentLocation(fix.lat, fix.lon);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(zh: '已使用你的当前位置', en: 'Using your current location'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addManual() async {
    if (widget.store.atSavedLimit) {
      showProSheet(context, widget.store);
      return;
    }
    final result = await showDialog<SavedLocation>(
      context: context,
      builder: (context) => const _AddLocationDialog(),
    );
    if (result != null) {
      final added = widget.store.addSaved(result.name, result.lat, result.lon);
      if (added != null) widget.store.selectSaved(added);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            FilledButton.icon(
              onPressed: _locating ? null : _useCurrent,
              icon: _locating
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(_locating
                  ? tr(zh: '定位中…', en: 'Locating…')
                  : tr(zh: '使用当前位置', en: 'Use current location')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addManual,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(tr(zh: '添加拍摄机位', en: 'Add a shooting spot')),
            ),
            const SizedBox(height: 20),
            if (store.hasActive) ...[
              Text(tr(zh: '当前使用', en: 'Active'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Card(
                child: ListTile(
                  leading: Icon(
                      store.activeName == 'Current location'
                          ? Icons.my_location
                          : Icons.place,
                      color: Theme.of(context).colorScheme.primary),
                  // 'Current location' is the store's persisted sentinel;
                  // translate at display time only.
                  title: Text(store.activeName == 'Current location'
                      ? tr(zh: '当前位置', en: 'Current location')
                      : store.activeName),
                  subtitle: Text(_coord(store.activeLat!, store.activeLon!)),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Text(tr(zh: '已存机位', en: 'Saved spots'),
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (!store.pro)
                  Text(
                      tr(
                          zh: '免费版:${store.saved.length}/${LocationStore.freeSavedLimit}',
                          en: 'Free: ${store.saved.length}/${LocationStore.freeSavedLimit}'),
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (store.saved.isEmpty)
              const _NoSavedSpots()
            else
              ...store.saved.map((loc) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(loc.name),
                      subtitle: Text(loc.coordLabel),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: tr(zh: '删除', en: 'Delete'),
                        onPressed: () => store.deleteSaved(loc),
                      ),
                      onTap: () {
                        store.selectSaved(loc);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(tr(
                                  zh: '正在为「${loc.name}」规划光线',
                                  en: 'Planning light for ${loc.name}'))),
                        );
                      },
                    ),
                  )),
            if (!store.pro && store.saved.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => showProSheet(context, store),
                icon: const Icon(Icons.lock_open, size: 18),
                label: Text(tr(zh: '解锁 Pro,保存无限机位', en: 'Unlock Pro for unlimited spots')),
              ),
            ],
          ],
        );
      },
    );
  }

  String _coord(double lat, double lon) {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}°$ns, ${lon.abs().toStringAsFixed(4)}°$ew';
  }
}

/// Warm empty state for the saved-spots list — a soft tinted icon, a heading
/// and a supporting line, matching the tone of the no-location view rather than
/// a single cold sentence.
class _NoSavedSpots extends StatelessWidget {
  const _NoSavedSpots();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bookmark_add_outlined, size: 30, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(
            tr(zh: '还没有已存机位', en: 'No saved spots yet'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
                zh: '添加你钟爱的拍摄机位,随时查看那里的黄金时段与日月方位。',
                en: 'Add a shooting spot you love to see its golden hour and '
                    'sun & moon bearings any day.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }
}

class _AddLocationDialog extends StatefulWidget {
  const _AddLocationDialog();
  @override
  State<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<_AddLocationDialog> {
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _submit() {
    final lat = double.tryParse(_lat.text.trim());
    final lon = double.tryParse(_lon.text.trim());
    if (lat == null || lon == null || !validCoord(lat, lon)) {
      setState(() => _error = tr(
          zh: '请输入有效的纬度(-90..90)和经度(-180..180)',
          en: 'Enter valid latitude (-90..90) and longitude (-180..180)'));
      return;
    }
    Navigator.of(context).pop(SavedLocation(id: '', name: _name.text, lat: lat, lon: lon));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(zh: '添加机位', en: 'Add a spot')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: tr(zh: '名称(如:悬崖观景位)', en: 'Name (e.g. Cliff viewpoint)')),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lat,
            decoration: InputDecoration(
                labelText: tr(zh: '纬度', en: 'Latitude'), hintText: '37.8199'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          TextField(
            controller: _lon,
            decoration: InputDecoration(
                labelText: tr(zh: '经度', en: 'Longitude'), hintText: '-122.4783'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(zh: '取消', en: 'Cancel'))),
        FilledButton(onPressed: _submit, child: Text(tr(zh: '添加', en: 'Add'))),
      ],
    );
  }
}
