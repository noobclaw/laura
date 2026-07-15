import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// In-memory model of projects, photos and settings, backed by a JSON file in
/// the app documents directory. Photo pixels are stored as JPEG files in a
/// `photos/` subfolder. Nothing ever leaves the device.
class FieldStampStore extends ChangeNotifier {
  FieldStampStore();

  /// Free tier: reports/CSV limited to this many photos; Pro removes the cap.
  static const int freeExportLimit = 5;

  final List<Project> projects = [];
  final List<StampPhoto> photos = [];
  String currentProjectId = 'default';
  CoordFormat coordFormat = CoordFormat.decimal;
  AltUnit altUnit = AltUnit.meters;
  bool pro = false;
  bool loaded = false;

  Directory? _photosDir;
  int _idSeq = 0;

  String _newId(String prefix) {
    _idSeq += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idSeq';
  }

  Project get currentProject => projects.firstWhere(
        (p) => p.id == currentProjectId,
        orElse: () =>
            projects.isNotEmpty ? projects.first : Project(id: 'default', name: 'Default'),
      );

  String projectName(String id) => projects
      .firstWhere((p) => p.id == id, orElse: () => Project(id: id, name: 'Default'))
      .name;

  String photoPath(String fileName) => '${_photosDir?.path ?? ''}/$fileName';

  /// Photos of a project, newest first.
  List<StampPhoto> photosForProject(String id) {
    final list = photos.where((p) => p.projectId == id).toList();
    list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return list;
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/fieldstamp.json');
  }

  /// Load state from disk. Any failure (first launch, or plugins unavailable in
  /// a test harness) leaves an empty but usable store with a default project.
  Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _photosDir = Directory('${docs.path}/photos');
      if (!await _photosDir!.exists()) {
        await _photosDir!.create(recursive: true);
      }
      final f = await _stateFile();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        pro = raw['pro'] as bool? ?? false;
        currentProjectId = raw['currentProjectId'] as String? ?? 'default';
        coordFormat = CoordFormat.values[(raw['coordFormat'] as int? ?? 0)
            .clamp(0, CoordFormat.values.length - 1)];
        altUnit = AltUnit.values[(raw['altUnit'] as int? ?? 0)
            .clamp(0, AltUnit.values.length - 1)];
        projects
          ..clear()
          ..addAll((raw['projects'] as List<dynamic>? ?? [])
              .map((e) => Project.fromJson(e as Map<String, dynamic>)));
        photos
          ..clear()
          ..addAll((raw['photos'] as List<dynamic>? ?? [])
              .map((e) => StampPhoto.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('fieldstamp load skipped: $e');
    } finally {
      if (projects.isEmpty) {
        projects.add(Project(id: 'default', name: 'Default project'));
        currentProjectId = 'default';
      }
      if (!projects.any((p) => p.id == currentProjectId)) {
        currentProjectId = projects.first.id;
      }
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final f = await _stateFile();
      await f.writeAsString(
        jsonEncode({
          'pro': pro,
          'currentProjectId': currentProjectId,
          'coordFormat': coordFormat.index,
          'altUnit': altUnit.index,
          'projects': projects.map((p) => p.toJson()).toList(),
          'photos': photos.map((p) => p.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('fieldstamp save skipped: $e');
    }
  }

  /// Persist a freshly stamped JPEG and its metadata. Returns the record, or
  /// null if the file could not be written.
  Future<StampPhoto?> saveCapture(
      Uint8List jpegBytes, StampReading reading, String projectId) async {
    try {
      final dir = _photosDir;
      if (dir == null) return null;
      final id = _newId('img');
      final fileName = '$id.jpg';
      await File('${dir.path}/$fileName').writeAsBytes(jpegBytes, flush: true);
      final photo = StampPhoto(
        id: id,
        fileName: fileName,
        projectId: projectId,
        capturedAt: reading.time,
        latitude: reading.latitude,
        longitude: reading.longitude,
        altitude: reading.altitude,
        accuracy: reading.accuracy,
        heading: reading.heading,
      );
      photos.add(photo);
      await _save();
      return photo;
    } catch (e) {
      debugPrint('saveCapture failed: $e');
      return null;
    }
  }

  Future<void> deletePhoto(StampPhoto p) async {
    try {
      final file = File(photoPath(p.fileName));
      if (await file.exists()) await file.delete();
    } catch (_) {}
    photos.remove(p);
    await _save();
  }

  Project addProject(String name) {
    final p = Project(id: _newId('proj'), name: name.trim());
    projects.add(p);
    currentProjectId = p.id;
    _save();
    return p;
  }

  void renameProject(Project p, String name) {
    p.name = name.trim();
    _save();
  }

  Future<void> deleteProject(Project p) async {
    if (projects.length <= 1) return; // keep at least one
    for (final photo in photos.where((x) => x.projectId == p.id).toList()) {
      await deletePhoto(photo);
    }
    projects.remove(p);
    if (currentProjectId == p.id) currentProjectId = projects.first.id;
    await _save();
  }

  void selectProject(String id) {
    currentProjectId = id;
    _save();
  }

  void updateNote(StampPhoto p, String note) {
    p.note = note;
    _save();
  }

  void setCoordFormat(CoordFormat f) {
    coordFormat = f;
    _save();
  }

  void setAltUnit(AltUnit u) {
    altUnit = u;
    _save();
  }

  void unlockPro() {
    pro = true;
    _save();
  }
}
