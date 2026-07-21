import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Persists the user's saved shooting locations, the currently selected
/// location, and the Pro unlock flag as a single JSON file in the app sandbox.
/// Nothing leaves the device.
class LocationStore extends ChangeNotifier {
  LocationStore();

  /// Free tier keeps one saved spot; Pro removes the cap.
  static const int freeSavedLimit = 1;

  final List<SavedLocation> saved = [];

  /// The active location the almanac is computed for. Null until GPS or a
  /// saved spot supplies coordinates.
  double? activeLat;
  double? activeLon;
  String activeName = 'Current location';

  bool pro = false;
  bool loaded = false;
  int _idSeq = 0;

  bool get hasActive => activeLat != null && activeLon != null;
  bool get atSavedLimit => !pro && saved.length >= freeSavedLimit;

  String _newId() {
    _idSeq += 1;
    return 'loc-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/goldenscout.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        saved
          ..clear()
          ..addAll((raw['saved'] as List<dynamic>? ?? [])
              .map((e) => SavedLocation.fromJson(e as Map<String, dynamic>)));
        final al = raw['activeLat'], ao = raw['activeLon'];
        if (al is num && ao is num) {
          activeLat = al.toDouble();
          activeLon = ao.toDouble();
          activeName = raw['activeName'] as String? ?? 'Saved location';
        }
      }
    } catch (e) {
      debugPrint('goldenscout load skipped: $e');
    } finally {
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'pro': pro,
          'saved': saved.map((e) => e.toJson()).toList(),
          'activeLat': activeLat,
          'activeLon': activeLon,
          'activeName': activeName,
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('goldenscout save skipped: $e');
    }
  }

  /// Point the almanac at a live GPS fix.
  void useCurrentLocation(double lat, double lon) {
    activeLat = lat;
    activeLon = lon;
    activeName = 'Current location';
    _save();
  }

  /// Point the almanac at an already-saved spot.
  void selectSaved(SavedLocation loc) {
    activeLat = loc.lat;
    activeLon = loc.lon;
    activeName = loc.name;
    _save();
  }

  /// Add a manual spot. Returns null and does nothing when the free cap is hit.
  SavedLocation? addSaved(String name, double lat, double lon) {
    if (atSavedLimit) return null;
    final loc = SavedLocation(
      id: _newId(),
      name: name.trim().isEmpty ? 'Saved spot' : name.trim(),
      lat: lat,
      lon: lon,
    );
    saved.add(loc);
    _save();
    return loc;
  }

  void deleteSaved(SavedLocation loc) {
    saved.remove(loc);
    _save();
  }

  void unlockPro() {
    pro = true;
    _save();
  }
}
