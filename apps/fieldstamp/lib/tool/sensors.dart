import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';

/// Streams the device GPS position (with altitude/accuracy) and magnetometer
/// heading, exposing the latest values as a [StampReading]. Everything is a
/// local device sensor — no network involved.
class SensorHub extends ChangeNotifier {
  double? _lat;
  double? _lon;
  double? _alt;
  double? _acc;
  double? _heading;

  bool _locationReady = false;
  String? _locationError;
  bool _started = false;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  bool get locationReady => _locationReady;
  String? get locationError => _locationError;
  double? get heading => _heading;
  double? get accuracy => _acc;

  StampReading snapshot() => StampReading(
        latitude: _lat,
        longitude: _lon,
        altitude: _alt,
        accuracy: _acc,
        heading: _heading,
        time: DateTime.now(),
      );

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _startLocation();
    _startCompass();
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationError = 'Location services are turned off';
        notifyListeners();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _locationError = 'Location permission denied';
        notifyListeners();
        return;
      }
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen(
        (p) {
          _lat = p.latitude;
          _lon = p.longitude;
          _alt = p.altitude;
          _acc = p.accuracy;
          _locationReady = true;
          _locationError = null;
          notifyListeners();
        },
        onError: (Object e) {
          _locationError = 'GPS error: $e';
          notifyListeners();
        },
      );
    } catch (e) {
      _locationError = 'GPS unavailable: $e';
      notifyListeners();
    }
  }

  void _startCompass() {
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (e) {
          _heading = e.heading;
          notifyListeners();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Magnetometer not present — bearing simply stays unavailable.
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }
}
