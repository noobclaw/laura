import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Streams the device magnetometer heading so the compass rose can rotate to
/// match where the phone is pointing. Location is fetched on demand (one-shot)
/// rather than streamed — the almanac only needs a fix, not continuous updates.
class SensorHub extends ChangeNotifier {
  double? _heading;
  StreamSubscription<CompassEvent>? _compassSub;
  bool _started = false;

  /// Device compass heading in degrees (clockwise from North), or null when no
  /// magnetometer is present.
  double? get heading => _heading;
  bool get hasCompass => _heading != null;

  void startCompass() {
    if (_started) return;
    _started = true;
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (e) {
          if (e.heading == null) return;
          _heading = e.heading;
          notifyListeners();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Magnetometer not present — heading simply stays null.
    }
  }

  /// A one-shot GPS fix. Throws a human-readable message on any failure so the
  /// caller can surface it.
  static Future<({double lat, double lon})> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Location services are turned off';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw 'Location permission denied';
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return (lat: p.latitude, lon: p.longitude);
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }
}
