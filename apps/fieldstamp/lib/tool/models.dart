// Plain data models for FieldStamp. No plugins here so this layer is unit
// testable and safe to import anywhere.

/// A snapshot of the device sensors at the moment a photo is taken (or shown
/// live under the viewfinder). Any field may be null before a fix is acquired.
class StampReading {
  const StampReading({
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.heading,
    required this.time,
  });

  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? accuracy;
  final double? heading;
  final DateTime time;

  bool get hasFix => latitude != null && longitude != null;
}

/// One captured, geo-stamped photo. The pixels live in a JPEG file inside the
/// app sandbox; [fileName] points to it. The coordinates are also kept in the
/// record so reports/CSV can be rebuilt without re-reading EXIF.
class StampPhoto {
  StampPhoto({
    required this.id,
    required this.fileName,
    required this.projectId,
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.heading,
    this.note = '',
  });

  final String id;
  final String fileName;
  String projectId;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? accuracy;
  final double? heading;
  String note;

  bool get hasFix => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'projectId': projectId,
        'capturedAt': capturedAt.toIso8601String(),
        'lat': latitude,
        'lon': longitude,
        'alt': altitude,
        'acc': accuracy,
        'hdg': heading,
        'note': note,
      };

  static StampPhoto fromJson(Map<String, dynamic> j) => StampPhoto(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        projectId: j['projectId'] as String? ?? 'default',
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        latitude: (j['lat'] as num?)?.toDouble(),
        longitude: (j['lon'] as num?)?.toDouble(),
        altitude: (j['alt'] as num?)?.toDouble(),
        accuracy: (j['acc'] as num?)?.toDouble(),
        heading: (j['hdg'] as num?)?.toDouble(),
        note: j['note'] as String? ?? '',
      );
}

/// A named project / work order that photos are filed under.
class Project {
  Project({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static Project fromJson(Map<String, dynamic> j) =>
      Project(id: j['id'] as String, name: j['name'] as String);
}

enum CoordFormat { decimal, dms }

enum AltUnit { meters, feet }
