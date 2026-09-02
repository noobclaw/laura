import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/l10n.dart';

/// Why a one-shot fix failed, so the screen can offer the matching exit.
enum LocationFailureKind { denied, deniedForever, serviceOff, other }

class LocationFailure implements Exception {
  LocationFailure(this.kind, this.message);

  final LocationFailureKind kind;

  /// Finished, translated sentence for the user.
  final String message;

  @override
  String toString() => message;
}

/// The two numbers the alignment screen needs: which way the phone points
/// (magnetometer) and how far back it is tilted (accelerometer). Together they
/// turn "azimuth 312, elevation 47" into "turn until the needle lines up, then
/// raise the phone until the bar centres".
///
/// Both are optional. A device with no magnetometer still gets the numbers and
/// a written instruction — the screen degrades, it never blanks.
///
/// ⚠️ The heading reported here is **magnetic** on both platforms and the
/// alignment screen adds the user's declination. Android's rotation-vector
/// azimuth is magnetic by definition; on iOS we read the plugin's
/// `headingForCameraMode`, which flutter_compass derives from the attitude
/// matrix in the *xMagneticNorthZVertical* reference frame — also magnetic
/// (only its plain `heading` is Core Location's true heading, and that one
/// is the wrong axis for aiming). Re-audit 2026-09-02 caught the earlier
/// assumption that iOS was already true north.
class SensorHub extends ChangeNotifier {
  /// Kept as a named constant so the declination logic reads as a decision
  /// rather than a missing branch. See the class comment.
  static const bool headingIsTrueNorth = false;

  double? _headingDeg;
  double? _pitchDeg;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  /// How many screens currently want live sensor data. The hub lives as long as
  /// the app does (it hangs off the tool module), so without this the very first
  /// visit to the alignment screen would leave the magnetometer and the
  /// accelerometer registered for the rest of the process — a background drain
  /// on an app whose whole pitch is that it does nothing behind your back.
  int _users = 0;

  double? get headingDeg => _headingDeg;

  /// How far above the horizon the back of the phone is aimed, in degrees.
  /// -90 is flat on a table (screen up), 0 is upright, +90 is aimed at zenith.
  double? get pitchDeg => _pitchDeg;

  bool get hasCompass => _headingDeg != null;
  bool get hasTilt => _pitchDeg != null;
  bool get running => _users > 0;

  static String get magneticNote => tr(
        zh: '罗盘读的是磁北。你所在地的磁偏角可以在观测点页里填,填了才是真方位。',
        en: 'The compass reads magnetic north. Set your local magnetic declination on the site screen to align against true bearings.',
      );

  /// Begin (or join) a sensor session. Every [acquire] must be matched by a
  /// [release].
  void acquire() {
    _users++;
    if (_users > 1) return;
    _startCompass();
    _startAccelerometer();
  }

  void release() {
    if (_users == 0) return;
    _users--;
    if (_users > 0) return;
    _compassSub?.cancel();
    _compassSub = null;
    _accelSub?.cancel();
    _accelSub = null;
    // Keep the last readings so a screen re-entered within a second does not
    // flash its "no sensor" fallback before the first event arrives.
  }

  void _startCompass() {
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _compassSub = events.listen(
        (e) {
          // This screen aims with the BACK of the phone (see pitch below).
          // On iOS `heading` is the bearing of the phone's top edge, which
          // is up to 180° off once the phone is held upright to point at
          // the sky; `headingForCameraMode` is the plugin's yaw out of the
          // back, exactly the axis we want. Android fills only `heading`,
          // and its rotation-vector azimuth is fine for an upright phone.
          final h = Platform.isIOS
              ? (e.headingForCameraMode ?? e.heading)
              : e.heading;
          if (h == null) return;
          // Core Location reports -1 while the heading is unavailable (no
          // location permission yet, needs calibration). The old guard of
          // `< -180` let that through and pegged the dial at 359°.
          if (Platform.isIOS && h < 0) return;
          if (h < -180 || h > 360) return;
          final normalised = h < 0 ? h + 360.0 : h;
          if (_headingDeg != null && (_headingDeg! - normalised).abs() < 0.3) {
            return; // below the noise floor of a handheld magnetometer
          }
          _headingDeg = normalised;
          notifyListeners();
        },
        onError: (Object e) => debugPrint('compass unavailable: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('compass unavailable: $e');
    }
  }

  void _startAccelerometer() {
    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        (e) {
          final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
          if (magnitude < 1e-3) return;
          // Gravity in device axes: the back of the phone is -z, so its
          // elevation above the horizon is asin(-z/|g|). Lightly smoothed so
          // the readout does not twitch in the hand.
          final raw =
              math.asin((-e.z / magnitude).clamp(-1.0, 1.0)) * 180 / math.pi;
          final next = _pitchDeg == null ? raw : _pitchDeg! * 0.8 + raw * 0.2;
          if (_pitchDeg != null && (_pitchDeg! - next).abs() < 0.2) {
            return; // 10 Hz of imperceptible change is 10 Hz of wasted rebuilds
          }
          _pitchDeg = next;
          notifyListeners();
        },
        onError: (Object e) => debugPrint('accelerometer unavailable: $e'),
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('accelerometer unavailable: $e');
    }
  }

  /// A one-shot GPS fix. Throws a [LocationFailure] on every failure path —
  /// a message the UI can show plus the [LocationFailureKind] that decides
  /// which button to put next to it — so no caller can fail silently or
  /// leave the user without an exit.
  static Future<({double lat, double lon, double altKm})> currentFix() async {
    try {
      // Permission first, service switch second: the OS prompt is what
      // creates the Settings toggle on iOS, and a user who turns the
      // service on afterwards should not be asked from scratch.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw LocationFailure(
          LocationFailureKind.deniedForever,
          tr(
            zh: '定位权限已被永久拒绝——请到系统设置里开启,或手动输入坐标',
            en: 'Location permission permanently denied — enable it in Settings, or enter coordinates manually',
          ),
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        throw LocationFailure(
          LocationFailureKind.denied,
          tr(
            zh: '定位权限被拒绝——可以手动输入坐标继续',
            en: 'Location permission denied — you can enter coordinates manually instead',
          ),
        );
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw LocationFailure(
          LocationFailureKind.serviceOff,
          tr(
            zh: '定位服务未开启——请打开系统定位,或手动输入坐标',
            en: 'Location services are off — turn them on, or enter coordinates manually',
          ),
        );
      }
      try {
        // A pass prediction is insensitive to a few hundred metres, and medium
        // accuracy gets a fix far faster than high does indoors.
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 20),
          ),
        );
        return (lat: p.latitude, lon: p.longitude, altKm: p.altitude / 1000.0);
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return (
            lat: last.latitude,
            lon: last.longitude,
            altKm: last.altitude / 1000.0
          );
        }
        throw LocationFailure(
          LocationFailureKind.other,
          tr(
            zh: 'GPS 定位超时——到窗边或室外再试,或手动输入坐标',
            en: 'GPS timed out — try near a window or outdoors, or enter coordinates manually',
          ),
        );
      }
    } on LocationFailure {
      rethrow; // already classified and translated
    } catch (e) {
      // Anything else the platform can raise — the service being switched off
      // mid-fix, a permission request already in flight, an OEM quirk. Never
      // let a raw PlatformException string reach a Chinese-language screen.
      debugPrint('location failed: $e');
      throw LocationFailure(
        LocationFailureKind.other,
        tr(
          zh: '定位失败——可以手动输入坐标继续',
          en: 'Could not get a location fix — you can enter coordinates manually instead',
        ),
      );
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }
}

/// Smallest signed difference between two bearings, in degrees (-180..180].
double bearingDelta(double from, double to) {
  var d = (to - from) % 360.0;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}
