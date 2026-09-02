import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../core/l10n.dart';

/// Why a one-shot fix failed, so the screen can offer the matching exit
/// (Open Settings / Location settings / Ask again) instead of a red line.
enum LocationFailureKind { denied, deniedForever, serviceOff, other }

class LocationFailure implements Exception {
  LocationFailure(this.kind, this.message);

  final LocationFailureKind kind;

  /// Finished, translated sentence for the user.
  final String message;

  @override
  String toString() => message;
}

/// Streams the device magnetometer heading so the compass rose can rotate to
/// match where the phone is pointing. Location is fetched on demand (one-shot)
/// rather than streamed — the almanac only needs a fix, not continuous updates.
///
/// The compass is a *live* sensor and the app's whole pitch is that it does
/// nothing behind the user's back, so the stream only runs while a screen
/// asked for it ([startCompass] / [stopCompass]) and is dropped when the app
/// goes to the background.
class SensorHub extends ChangeNotifier {
  double? _heading;
  StreamSubscription<CompassEvent>? _compassSub;

  /// Device compass heading in degrees (clockwise from North), or null when no
  /// usable magnetometer reading exists.
  double? get heading => _heading;
  bool get hasCompass => _heading != null;
  bool get running => _compassSub != null;

  /// Below this the dial does not move: a handheld magnetometer jitters by a
  /// fraction of a degree constantly and every notify is a full rebuild.
  static const double _deadbandDeg = 0.6;

  void startCompass() {
    if (_compassSub != null) return;
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (e) {
          final h = e.heading;
          if (h == null) return;
          // iOS reports -1 until location is authorised (true heading needs
          // it). Android devices without a magnetometer deliver a constant
          // 0° with no accuracy at all. Neither is a bearing; showing one
          // would let the rose claim "aligned" while pointing anywhere.
          if (h < 0 || (Platform.isAndroid && e.accuracy == null && h == 0)) {
            if (_heading != null) {
              _heading = null;
              notifyListeners();
            }
            return;
          }
          final next = _smooth(_heading, h);
          if (_heading != null && _angleDiff(_heading!, next).abs() < _deadbandDeg) {
            return;
          }
          _heading = next;
          notifyListeners();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Magnetometer not present — heading simply stays null.
    }
  }

  void stopCompass() {
    _compassSub?.cancel();
    _compassSub = null;
  }

  /// Exponential smoothing on the circle (359° → 1° is a 2° move, not 358°).
  static double _smooth(double? prev, double raw) {
    if (prev == null) return raw;
    final d = _angleDiff(prev, raw);
    var v = prev + d * 0.35;
    if (v < 0) v += 360;
    if (v >= 360) v -= 360;
    return v;
  }

  static double _angleDiff(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// A one-shot GPS fix. Throws a [LocationFailure] on every failure path so
  /// the caller can show the message *and* the matching way out.
  static Future<({double lat, double lon})> currentFix() async {
    // Permission before the service switch: the OS prompt is what creates
    // the toggle in iOS Settings, and a user who turns location on afterwards
    // should not have to be asked from scratch.
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.unableToDetermine) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw LocationFailure(
        LocationFailureKind.deniedForever,
        tr(
          zh: '定位权限已被永久拒绝——请到系统设置开启,或手动输入坐标',
          en: 'Location permission permanently denied — enable it in Settings, or enter coordinates manually',
        ),
      );
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.unableToDetermine) {
      throw LocationFailure(
        LocationFailureKind.denied,
        tr(zh: '定位权限被拒绝——可以手动输入坐标', en: 'Location permission denied — you can enter coordinates manually'),
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationFailure(
        LocationFailureKind.serviceOff,
        tr(zh: '定位服务未开启——请打开系统定位,或手动输入坐标', en: 'Location services are off — turn them on, or enter coordinates manually'),
      );
    }
    try {
      // Medium accuracy acquires much faster than high and is far more precise
      // than the almanac needs; the timeLimit stops the indoor/cold-GPS case
      // from spinning forever.
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (lat: p.latitude, lon: p.longitude);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (lat: last.latitude, lon: last.longitude);
      throw LocationFailure(
        LocationFailureKind.other,
        tr(
          zh: 'GPS 定位超时——请到开阔处重试,或手动输入坐标',
          en: 'GPS timed out — move somewhere with sky view, or enter coordinates manually',
        ),
      );
    } on LocationFailure {
      rethrow;
    } catch (e) {
      debugPrint('location failed: $e');
      throw LocationFailure(
        LocationFailureKind.other,
        tr(zh: '定位失败——可以手动输入坐标', en: 'Could not get a fix — you can enter coordinates manually'),
      );
    }
  }

  static Future<bool> openAppSettings() => Geolocator.openAppSettings();
  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }
}
