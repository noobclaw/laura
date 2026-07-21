/// A saved shooting location. Coordinates are stored in decimal degrees.
class SavedLocation {
  final String id;
  String name;
  double lat;
  double lon;

  SavedLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
      };

  factory SavedLocation.fromJson(Map<String, dynamic> j) => SavedLocation(
        id: j['id'] as String,
        name: (j['name'] as String?)?.trim().isNotEmpty == true
            ? j['name'] as String
            : 'Saved spot',
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );

  /// A short "12.3456°N, 65.4321°W" style label.
  String get coordLabel {
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(4)}°$ns, ${lon.abs().toStringAsFixed(4)}°$ew';
  }
}

/// True when a latitude/longitude pair is within valid geographic bounds.
bool validCoord(double lat, double lon) =>
    lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
