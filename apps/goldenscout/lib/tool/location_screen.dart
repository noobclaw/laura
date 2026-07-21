import 'package:flutter/material.dart';

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
          const SnackBar(content: Text('Using your current location')),
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
              label: Text(_locating ? 'Locating…' : 'Use current location'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addManual,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a shooting spot'),
            ),
            const SizedBox(height: 20),
            if (store.hasActive) ...[
              Text('Active', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Card(
                child: ListTile(
                  leading: Icon(
                      store.activeName == 'Current location'
                          ? Icons.my_location
                          : Icons.place,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(store.activeName),
                  subtitle: Text(_coord(store.activeLat!, store.activeLon!)),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Text('Saved spots', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (!store.pro)
                  Text('Free: ${store.saved.length}/${LocationStore.freeSavedLimit}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (store.saved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No saved spots yet.',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              ...store.saved.map((loc) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(loc.name),
                      subtitle: Text(loc.coordLabel),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => store.deleteSaved(loc),
                      ),
                      onTap: () {
                        store.selectSaved(loc);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Planning light for ${loc.name}')),
                        );
                      },
                    ),
                  )),
            if (!store.pro && store.saved.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => showProSheet(context, store),
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Unlock Pro for unlimited spots'),
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
      setState(() => _error = 'Enter valid latitude (-90..90) and longitude (-180..180)');
      return;
    }
    Navigator.of(context).pop(SavedLocation(id: '', name: _name.text, lat: lat, lon: lon));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a spot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (e.g. Cliff viewpoint)'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lat,
            decoration: const InputDecoration(labelText: 'Latitude', hintText: '37.8199'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          TextField(
            controller: _lon,
            decoration: const InputDecoration(labelText: 'Longitude', hintText: '-122.4783'),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
