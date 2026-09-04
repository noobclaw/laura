import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../core/l10n.dart';
import 'models.dart';

/// Why the app has no usable position right now. Each state maps to one
/// user action on the camera screen (retry / open app settings / open
/// location settings), so the failure is never a dead end.
enum LocationState { pending, ok, serviceOff, denied, deniedForever, error }

/// Streams the device GPS position (with altitude/accuracy) and magnetometer
/// heading, exposing the latest values as a [StampReading]. Everything is a
/// local device sensor — no network involved.
class SensorHub extends ChangeNotifier {
  double? _lat;
  double? _lon;
  double? _alt;
  double? _acc;
  double? _heading;

  /// When the last position arrived. A fix older than [staleAfter] is no
  /// longer burned into photos as if it were current: an evidence camera
  /// that stamps the car-park coordinates onto a basement photo is worse
  /// than one that says "no GPS fix".
  DateTime? _fixAt;
  static const Duration staleAfter = Duration(seconds: 120);

  LocationState _state = LocationState.pending;
  String? _detail;
  bool _started = false;
  bool _locating = false;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  LocationState get locationState => _state;

  /// Raw platform error text for [LocationState.error]; null otherwise.
  String? get locationDetail => _detail;

  bool get fixIsStale =>
      _fixAt != null && DateTime.now().difference(_fixAt!) > staleAfter;

  /// Seconds since the last fix, for the "last fix 3 min ago" hint.
  int? get secondsSinceFix =>
      _fixAt == null ? null : DateTime.now().difference(_fixAt!).inSeconds;

  bool get locationReady =>
      _state == LocationState.ok && _lat != null && !fixIsStale;

  /// One-line, user-facing description of the current problem, or null when
  /// positioning works. Kept for the info band; the state itself drives
  /// which button appears next to it.
  String? get locationError {
    switch (_state) {
      case LocationState.ok:
        return fixIsStale
            ? tr(zh: 'GPS 信号丢失', en: 'GPS signal lost')
            : null;
      case LocationState.pending:
        return null;
      case LocationState.serviceOff:
        return tr(zh: '定位服务已关闭', en: 'Location services are turned off');
      case LocationState.denied:
        return tr(zh: '未授予定位权限', en: 'Location permission not granted');
      case LocationState.deniedForever:
        return tr(
          zh: '定位权限已被永久拒绝',
          en: 'Location permission permanently denied',
        );
      case LocationState.error:
        return tr(zh: 'GPS 不可用', en: 'GPS unavailable');
    }
  }

  double? get heading => _heading;
  double? get accuracy => _acc;

  StampReading snapshot() {
    final usable = _state == LocationState.ok && !fixIsStale;
    return StampReading(
      latitude: usable ? _lat : null,
      longitude: usable ? _lon : null,
      altitude: usable ? _alt : null,
      accuracy: usable ? _acc : null,
      heading: _heading,
      time: DateTime.now(),
    );
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _startCompass();
    await retryLocation();
  }

  /// Re-run the whole service/permission/stream setup. Called at start, from
  /// the "try again" button, and every time the app returns to the
  /// foreground without a working position — the user has very likely just
  /// flipped the switch we asked them to.
  Future<void> retryLocation() async {
    if (_locating) return;
    _locating = true;
    try {
      await _posSub?.cancel();
      _posSub = null;

      // iOS reports "denied" for the *authorisation* whenever the system
      // location switch is off, which geolocator maps to deniedForever — so
      // there the service check must come first or the user is told to fix
      // a permission that is fine. Android is the other way round: asking
      // for permission first is what makes the Settings toggle exist.
      if (Platform.isIOS && !await Geolocator.isLocationServiceEnabled()) {
        _set(LocationState.serviceOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.unableToDetermine) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _set(LocationState.deniedForever);
        return;
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.unableToDetermine) {
        _set(LocationState.denied);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(LocationState.serviceOff);
        return;
      }

      _set(LocationState.ok);
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).listen(
        (p) {
          _lat = p.latitude;
          _lon = p.longitude;
          // geolocator omits altitude when the fix has none (indoor / network
          // location) and the platform side then reads it as 0.0 — which
          // would be burned into the photo as "Alt 0 m". Only trust it when
          // the fix reports a vertical accuracy.
          _alt = p.altitudeAccuracy > 0 ? p.altitude : null;
          _acc = p.accuracy;
          _fixAt = DateTime.now();
          if (_state != LocationState.ok) _state = LocationState.ok;
          notifyListeners();
        },
        onError: (Object e) => _set(LocationState.error, '$e'),
      );
    } catch (e) {
      _set(LocationState.error, '$e');
    } finally {
      _locating = false;
    }
  }

  void _set(LocationState s, [String? detail]) {
    _state = s;
    _detail = detail;
    notifyListeners();
  }

  /// The two system-settings exits the info band offers. Both come from
  /// geolocator, so no extra permission plugin is needed.
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  void _startCompass() {
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (e) {
          // The bearing that matters is where the *camera* points. On iOS
          // `heading` is the top edge of an upright phone (skyward); the
          // plugin's headingForCameraMode is the yaw out of the back —
          // exactly the lens axis. Android's azimuth is fine for an
          // upright phone. Both are magnetic north (the plugin derives the
          // camera-mode yaw in a magnetic reference frame), so the burned
          // bearing means the same thing on both platforms.
          final h = Platform.isIOS
              ? (e.headingForCameraMode ?? e.heading)
              : e.heading;
          // iOS reports -1 while heading is unavailable (no location
          // permission yet); burning that in as "359° N" would be wrong.
          if (h == null || h < 0) {
            if (_heading != null) {
              _heading = null;
              notifyListeners();
            }
            return;
          }
          _heading = h;
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
