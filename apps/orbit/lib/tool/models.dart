import '../core/l10n.dart';
import 'sgp4.dart';

/// One catalogue entry: an element set plus the human-facing bits the raw TLE
/// does not carry (a Chinese name, a known brightness, whether it is one of the
/// free-tier headliners).
class SatEntry {
  SatEntry({
    required this.tle,
    this.nameZh,
    this.standardMagnitude,
    this.featured = false,
    this.imported = false,
  });

  final Tle tle;

  /// Curated Chinese name; falls back to the catalogue name when absent (rocket
  /// bodies and the like keep their designations in any language).
  final String? nameZh;

  /// Magnitude at 1000 km range, fully illuminated. Only set where a published
  /// value is well established — the rest stay null and the UI shows a dash
  /// instead of inventing a brightness.
  final double? standardMagnitude;

  /// Part of the free tier's eight headliners.
  final bool featured;

  /// Came from the user's own paste rather than the bundled snapshot.
  final bool imported;

  String get id => tle.satnum;
  String get displayName => nameZh == null ? tle.name : tr(zh: nameZh!, en: tle.name);
  String get subtitle {
    // Do not repeat the name back at the user when the curated name and the
    // catalogue name resolve to the same string (English locale, mostly).
    final name = displayName;
    return name == tle.name ? '#${tle.satnum}' : '${tle.name} · #${tle.satnum}';
  }
}

/// Curated names and brightnesses for the objects worth naming. Everything else
/// in the bundled snapshot is a rocket body or a research satellite that reads
/// the same in every language.
///
/// Standard magnitudes are the widely published values for these three; the rest
/// are deliberately absent (see [SatEntry.standardMagnitude]).
const Map<String, ({String zh, double? mag, bool featured})> curatedSatellites = {
  '25544': (zh: '国际空间站', mag: -1.8, featured: true),
  '48274': (zh: '中国空间站 · 天和', mag: -0.5, featured: true),
  '20580': (zh: '哈勃空间望远镜', mag: 2.4, featured: true),
  '25994': (zh: 'Terra 对地观测卫星', mag: null, featured: true),
  '27424': (zh: 'Aqua 对地观测卫星', mag: null, featured: true),
  '27386': (zh: 'Envisat 环境卫星', mag: null, featured: true),
  '16908': (zh: '阳光卫星 Ajisai', mag: null, featured: true),
  '61047': (zh: 'AST 蓝鸟 001', mag: null, featured: true),
  '39766': (zh: 'ALOS-2 大地 2 号', mag: null, featured: false),
  '57800': (zh: 'XRISM X 射线望远镜', mag: null, featured: false),
  '49044': (zh: '国际空间站 · 科学号', mag: null, featured: false),
};

/// One sampled instant along a pass — a point on the sky-dome curve.
class PassSample {
  const PassSample({
    required this.time,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.rangeKm,
    required this.sunlit,
    required this.magnitude,
  });

  final DateTime time;
  final double azimuthDeg, elevationDeg, rangeKm;
  final bool sunlit;
  final double? magnitude;

  Map<String, dynamic> toJson() => {
        't': time.toUtc().millisecondsSinceEpoch,
        'az': azimuthDeg,
        'el': elevationDeg,
        'r': rangeKm,
        's': sunlit,
        'm': magnitude,
      };

  static PassSample fromJson(Map<String, dynamic> j) => PassSample(
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int, isUtc: true),
        azimuthDeg: (j['az'] as num).toDouble(),
        elevationDeg: (j['el'] as num).toDouble(),
        rangeKm: (j['r'] as num).toDouble(),
        sunlit: j['s'] as bool,
        magnitude: (j['m'] as num?)?.toDouble(),
      );
}

/// Why a pass is or is not worth walking outside for. "Not visible" has two
/// completely different causes and telling users the wrong one is worse than
/// saying nothing: a satellite in the Earth's shadow is invisible no matter how
/// good your sky is, while a daylight pass is only invisible because the Sun is
/// up where *you* are.
enum PassVisibility {
  /// Satellite sunlit, observer's sky past civil twilight, above the horizon.
  visible,

  /// Satellite is in the Earth's shadow for the whole pass.
  eclipsed,

  /// Satellite is lit, but the observer's sky is too bright.
  daylight,
}

/// A single pass of one satellite over the observer.
class SatPass {
  const SatPass({
    required this.satId,
    required this.satName,
    required this.satNameZh,
    required this.start,
    required this.peak,
    required this.end,
    required this.startAzimuth,
    required this.peakAzimuth,
    required this.endAzimuth,
    required this.peakElevation,
    required this.peakRangeKm,
    required this.visibility,
    required this.brightestMagnitude,
    required this.track,
  });

  final String satId;
  final String satName;
  final String? satNameZh;

  /// Local-time instants of horizon-crossing, culmination, and set.
  final DateTime start, peak, end;
  final double startAzimuth, peakAzimuth, endAzimuth;
  final double peakElevation, peakRangeKm;

  final PassVisibility visibility;

  /// True when at least one sampled instant is naked-eye visible: satellite lit,
  /// observer's sky dark, above the horizon.
  bool get visible => visibility == PassVisibility.visible;
  final double? brightestMagnitude;
  final List<PassSample> track;

  String get displayName =>
      satNameZh == null ? satName : tr(zh: satNameZh!, en: satName);

  Duration get duration => end.difference(start);

  /// The visible portion, which can be shorter than the pass when the satellite
  /// flies into the Earth's shadow partway across the sky.
  List<PassSample> get visibleSamples => track
      .where((s) => s.sunlit && s.elevationDeg > 0)
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
        'id': satId,
        'name': satName,
        'zh': satNameZh,
        'start': start.toUtc().millisecondsSinceEpoch,
        'peak': peak.toUtc().millisecondsSinceEpoch,
        'end': end.toUtc().millisecondsSinceEpoch,
        'saz': startAzimuth,
        'paz': peakAzimuth,
        'eaz': endAzimuth,
        'pel': peakElevation,
        'prk': peakRangeKm,
        'vis': visibility.index,
        'mag': brightestMagnitude,
        'track': track.map((s) => s.toJson()).toList(),
      };

  static SatPass fromJson(Map<String, dynamic> j) => SatPass(
        satId: j['id'] as String,
        satName: j['name'] as String,
        satNameZh: j['zh'] as String?,
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int, isUtc: true)
            .toLocal(),
        peak: DateTime.fromMillisecondsSinceEpoch(j['peak'] as int, isUtc: true)
            .toLocal(),
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int, isUtc: true)
            .toLocal(),
        startAzimuth: (j['saz'] as num).toDouble(),
        peakAzimuth: (j['paz'] as num).toDouble(),
        endAzimuth: (j['eaz'] as num).toDouble(),
        peakElevation: (j['pel'] as num).toDouble(),
        peakRangeKm: (j['prk'] as num).toDouble(),
        visibility: PassVisibility.values[j['vis'] as int],
        brightestMagnitude: (j['mag'] as num?)?.toDouble(),
        track: (j['track'] as List<dynamic>)
            .map((e) => PassSample.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Where the user is watching from.
class ObserverSite {
  const ObserverSite({
    required this.latitude,
    required this.longitude,
    this.altitudeKm = 0.0,
    this.magneticDeclinationDeg = 0.0,
    this.name,
  });

  final double latitude, longitude, altitudeKm;

  /// Local magnetic declination in degrees (east positive) — the angle between
  /// magnetic north, which the phone's compass reads, and true north, which
  /// every bearing in this app is measured from. Zero until the user supplies
  /// it. It reaches 20 degrees or more at high latitudes, which is more than
  /// the alignment tolerance, so leaving it out entirely would let the app say
  /// "on target" while pointing at the wrong patch of sky.
  final double magneticDeclinationDeg;
  final String? name;

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        'alt': altitudeKm,
        'dec': magneticDeclinationDeg,
        'name': name,
      };

  static ObserverSite? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final lat = j['lat'], lon = j['lon'];
    if (lat is! num || lon is! num) return null;
    return ObserverSite(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      altitudeKm: (j['alt'] as num?)?.toDouble() ?? 0.0,
      magneticDeclinationDeg: (j['dec'] as num?)?.toDouble() ?? 0.0,
      name: j['name'] as String?,
    );
  }
}

/// How stale the bundled/imported elements are, and what that means for the
/// predictions built on them. Shown next to every prediction — the honest
/// alternative to quietly serving month-old orbits.
enum ElementFreshness { fresh, aging, stale }

ElementFreshness freshnessOf(double ageDays) {
  if (ageDays <= 7) return ElementFreshness.fresh;
  if (ageDays <= 30) return ElementFreshness.aging;
  return ElementFreshness.stale;
}

String freshnessLabel(ElementFreshness f) {
  switch (f) {
    case ElementFreshness.fresh:
      return tr(zh: '精确', en: 'Accurate');
    case ElementFreshness.aging:
      return tr(zh: '分钟级偏差', en: 'Minutes of drift');
    case ElementFreshness.stale:
      return tr(zh: '建议更新', en: 'Update recommended');
  }
}
