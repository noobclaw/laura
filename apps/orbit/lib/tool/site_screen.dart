import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'sensors.dart';
import 'store.dart';
import 'ui_common.dart';

/// Where you are watching from. GPS is the fast path; typing coordinates is a
/// first-class path, not a consolation prize — permission refusals and indoor
/// cold starts must never dead-end the app.
class SiteScreen extends StatefulWidget {
  const SiteScreen({super.key, required this.store});

  final OrbitStore store;

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _declController = TextEditingController();
  bool _locating = false;
  bool _applying = false;
  String? _error;
  String? _manualError;

  @override
  void initState() {
    super.initState();
    final s = widget.store.site;
    if (s != null) {
      _latController.text = s.latitude.toStringAsFixed(4);
      _lonController.text = s.longitude.toStringAsFixed(4);
      if (s.magneticDeclinationDeg != 0) {
        _declController.text = s.magneticDeclinationDeg.toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _declController.dispose();
    super.dispose();
  }

  double get _declinationInput =>
      double.tryParse(_declController.text.trim()) ?? 0.0;

  Future<void> _useGps() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final fix = await SensorHub.currentFix();
      if (!mounted) return;
      _latController.text = fix.lat.toStringAsFixed(4);
      _lonController.text = fix.lon.toStringAsFixed(4);
      await widget.store.setSite(ObserverSite(
        latitude: fix.lat,
        longitude: fix.lon,
        altitudeKm: fix.altKm.clamp(-0.5, 9.0),
        magneticDeclinationDeg: _declinationInput,
        name: tr(zh: '当前位置', en: 'Current location'),
      ));
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(zh: '观测点已更新', en: 'Observing site updated'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _useManual() async {
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      setState(() => _manualError = tr(
            zh: '请输入有效坐标:纬度 -90~90,经度 -180~180',
            en: 'Enter valid coordinates: latitude -90..90, longitude -180..180',
          ));
      return;
    }
    final decl = _declController.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_declController.text.trim());
    if (decl == null || decl.abs() > 90) {
      setState(() => _manualError = tr(
            zh: '磁偏角请填 -90~90 之间的数字（东偏为正），或留空。',
            en: 'Magnetic declination must be a number between -90 and 90 (east positive), or blank.',
          ));
      return;
    }
    setState(() {
      _manualError = null;
      _applying = true;
    });
    await widget.store.setSite(ObserverSite(
      latitude: lat,
      longitude: lon,
      magneticDeclinationDeg: decl,
      name: tr(zh: '手动输入', en: 'Entered manually'),
    ));
    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(zh: '观测点已更新', en: 'Observing site updated'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site = widget.store.site;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (site != null) _CurrentSiteCard(site: site),
        if (site != null) const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(zh: '用 GPS 取点', en: 'Use GPS'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  tr(
                    zh: '只取一次定位,不后台追踪。坐标只留在这台设备上。',
                    en: 'A single fix, no background tracking. The coordinates never leave this device.',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _locating ? null : _useGps,
                    icon: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 20),
                    label: Text(_locating
                        ? tr(zh: '定位中…', en: 'Locating…')
                        : tr(zh: '定位到我现在的位置', en: 'Locate me')),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: scheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                  height: 1.4,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(zh: '手动输入坐标', en: 'Enter coordinates'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  tr(
                    zh: '不想给定位权限、或在室内收不到 GPS 时用这个。北纬和东经为正。',
                    en: 'For when you would rather not grant location access, or GPS cannot see the sky. North and east are positive.',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                          labelText: tr(zh: '纬度', en: 'Latitude'),
                          hintText: '39.9042',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lonController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                          labelText: tr(zh: '经度', en: 'Longitude'),
                          hintText: '116.4074',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_manualError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _manualError!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _declController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: tr(
                        zh: '磁偏角（可选，度）',
                        en: 'Magnetic declination (optional, degrees)'),
                    hintText: tr(zh: '例如 -7.2', en: 'e.g. -7.2'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    zh: '手机罗盘指的是磁北，而过境方位用的是真北，两者差一个磁偏角。在中国大部地区大约 -2°~-10°，北美西部可达 +13°，高纬度更大。搜“magnetic declination + 你的城市”就能查到；留空则不修正。',
                    en: 'Your phone points at magnetic north; every bearing here is measured from true north, and the two differ by the local declination — roughly +13° on the US west coast, negative across most of China, larger still near the poles. Search "magnetic declination" plus your city. Leave blank to skip the correction.',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _applying ? null : _useManual,
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_applying
                        ? tr(zh: '应用中…', en: 'Applying…')
                        : tr(zh: '用这个坐标', en: 'Use these coordinates')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          tr(
            zh: '过境时刻对位置很敏感:相隔 100 公里,同一颗卫星的过境时间和方位就完全不同。',
            en: 'Pass times are position-sensitive: move 100 km and the same satellite passes at a different time, on a different bearing.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
        ),
      ],
    );
  }
}

class _CurrentSiteCard extends StatelessWidget {
  const _CurrentSiteCard({required this.site});
  final ObserverSite site;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration:
            BoxDecoration(gradient: skyGradient(Theme.of(context).brightness)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const StarFieldPainter(seed: 3, count: 40),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place, color: kOrbitCyan, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        site.name ?? tr(zh: '观测点', en: 'Observing site'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: tr(zh: '纬度', en: 'LATITUDE'),
                          value: '${site.latitude.toStringAsFixed(4)}°',
                          onLight: true,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: tr(zh: '经度', en: 'LONGITUDE'),
                          value: '${site.longitude.toStringAsFixed(4)}°',
                          onLight: true,
                        ),
                      ),
                      if (site.magneticDeclinationDeg != 0)
                        Expanded(
                          child: StatTile(
                            label: tr(zh: '磁偏角', en: 'DECLINATION'),
                            value:
                                '${site.magneticDeclinationDeg > 0 ? '+' : ''}${site.magneticDeclinationDeg.toStringAsFixed(1)}°',
                            onLight: true,
                          ),
                        ),
                    ],
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
