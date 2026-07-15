import 'models.dart';

/// Pure formatting helpers for coordinates, altitude, bearing and time.
/// Kept free of Flutter/plugin imports so they can be unit tested directly.

String formatLatLon(double? lat, double? lon, CoordFormat fmt) {
  if (lat == null || lon == null) return 'No GPS fix';
  switch (fmt) {
    case CoordFormat.decimal:
      return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
    case CoordFormat.dms:
      return '${_dms(lat, true)}  ${_dms(lon, false)}';
  }
}

String _dms(double value, bool isLat) {
  final hemi = isLat
      ? (value >= 0 ? 'N' : 'S')
      : (value >= 0 ? 'E' : 'W');
  final abs = value.abs();
  final deg = abs.floor();
  final minFull = (abs - deg) * 60;
  final min = minFull.floor();
  final sec = (minFull - min) * 60;
  return "$deg°${min.toString().padLeft(2, '0')}'${sec.toStringAsFixed(1)}\"$hemi";
}

String formatAltitude(double? altMeters, AltUnit unit) {
  if (altMeters == null) return '—';
  if (unit == AltUnit.feet) {
    return '${(altMeters * 3.28084).toStringAsFixed(0)} ft';
  }
  return '${altMeters.toStringAsFixed(0)} m';
}

const List<String> _compass8 = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

String formatHeading(double? deg) {
  if (deg == null) return '—';
  final d = ((deg % 360) + 360) % 360;
  final idx = (((d + 22.5) ~/ 45) % 8).toInt();
  return '${d.toStringAsFixed(0)}° ${_compass8[idx]}';
}

String formatTimestamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String formatDateHeader(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Quote a value for CSV output when it contains delimiters.
String csvField(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
