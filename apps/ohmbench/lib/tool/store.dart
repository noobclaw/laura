import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bench/atomic_file.dart';
import 'schematic/document.dart';

/// One saved circuit.
class Project {
  Project({
    required this.id,
    required this.name,
    required this.created,
    required this.updated,
    required this.document,
    this.scratch = false,
  });

  /// An example opened for a look: edited in memory, never written to disk
  /// and not counted against the free tier until the user saves a copy.
  /// Opening the built-in examples must not use up a free user's one
  /// circuit (2026-09-23 audit P1-3).
  final bool scratch;

  final String id;
  String name;
  final DateTime created;
  DateTime updated;
  SchematicDocument document;

  /// Parts that count toward the free tier's cap. Ground symbols and wires
  /// are free: a cap that charged for ground would push people into
  /// leaving it out, and a circuit without ground cannot be simulated.
  int get partCount => countedParts(document);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
        'doc': document.toJson(),
      };

  static Project fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Circuit',
        created: DateTime.fromMillisecondsSinceEpoch(
            (json['created'] as num?)?.toInt() ?? 0),
        updated: DateTime.fromMillisecondsSinceEpoch(
            (json['updated'] as num?)?.toInt() ?? 0),
        document: SchematicDocument.fromJson(
            (json['doc'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

int countedParts(SchematicDocument doc) =>
    doc.parts.where((p) => p.kind != PartKind.ground).length;

/// Every saved circuit plus the Pro flag.
///
/// Durability is the product (wedge ①, "Craps no components at all when
/// create"): the projects live in one atomically written file, every edit is
/// queued to disk within a fraction of a second, and the app flushes on
/// every trip to the background. The Pro flag lives in its own file so a
/// damaged project file can never revoke a purchase, and vice versa.
class ProjectStore extends ChangeNotifier {
  ProjectStore() {
    _file = AtomicJsonFile(
      'ohmbench_projects.json',
      onTrouble: _trouble,
      // Only a failed save is cured by a later successful one. A damaged
      // file set aside, or entries that could not be read, stay reported.
      onWritten: () {
        if (storageTrouble.value == 'save') storageTrouble.value = null;
      },
    );
    _proFile = AtomicJsonFile('ohmbench_pro.json', onTrouble: _trouble);
  }

  /// Free tier: one saved circuit of up to twelve parts. Enough for a
  /// divider, an RC filter or a smoothed rectifier — the whole simulator,
  /// the scope and undo stay unlocked.
  static const int freeProjects = 1;
  static const int freeParts = 12;

  late final AtomicJsonFile _file;
  late final AtomicJsonFile _proFile;

  /// A user-facing sentence when saving or loading went wrong, else null.
  /// The home screen and the editor show it as a banner — a save that fails
  /// silently is the one bug this app cannot have.
  final ValueNotifier<String?> storageTrouble = ValueNotifier<String?>(null);

  /// Set in [_trouble]; turned into words by the UI, which owns `tr()`.
  void _trouble(String kind, String detail) {
    debugPrint('storage $kind: $detail');
    storageTrouble.value = kind;
  }

  /// True when the projects file could not be read but may still hold the
  /// user's circuits. Saving is refused until the app restarts, so a
  /// transient read error can never become "your circuits were replaced by
  /// an empty list".
  bool get savingBlocked => _file.readFailed || _foreignFile;

  bool _foreignFile = false;

  final List<Project> projects = [];

  /// Raw entries that failed to parse. Written back verbatim on every save,
  /// so a project this version cannot read is kept for a later one instead
  /// of being dropped by the next edit.
  final List<Object?> _unreadable = [];
  bool pro = false;
  bool loaded = false;

  /// Pro reported by the store before [load] finished (StoreKit replays past
  /// purchases at launch). Applied once loading completes instead of being
  /// overwritten by the file's older value.
  bool _proPending = false;

  Timer? _saveTimer;

  bool get atProjectLimit => !pro && projects.length >= freeProjects;

  bool partLimitReached(SchematicDocument doc) =>
      !pro && countedParts(doc) >= freeParts;

  Project? byId(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    final proDoc = await _proFile.read();
    // Type-checked, not cast: a file that is valid JSON but not ours (a
    // future format, a hand edit) must degrade, never throw out of main().
    pro = proDoc?['pro'] == true;
    final raw = await _file.read();
    projects.clear();
    _unreadable.clear();
    final list = raw?['projects'];
    if (raw != null && list is! List) {
      // Something is there that this version does not understand. Keep it
      // untouched: treat it as unreadable and refuse to save over it.
      _foreignFile = true;
      storageTrouble.value = 'load';
    }
    for (final entry in (list is List ? list : const [])) {
      try {
        projects.add(Project.fromJson((entry as Map).cast<String, dynamic>()));
      } catch (e) {
        // One unreadable project must not take the others with it, and must
        // not be lost either: it is kept as-is and written back.
        debugPrint('project skipped: $e');
        _unreadable.add(entry);
      }
    }
    if (_unreadable.isNotEmpty) storageTrouble.value = 'skipped';
    _sort();
    loaded = true;
    if (_proPending) {
      _proPending = false;
      pro = true;
      _savePro();
    }
    notifyListeners();
  }

  void unlockPro() {
    if (!loaded) {
      _proPending = true;
      return;
    }
    if (pro) return;
    pro = true;
    _savePro();
    notifyListeners();
  }

  void _savePro() => _proFile.write({'pro': pro});

  String _newId() => 'p${DateTime.now().microsecondsSinceEpoch}';

  /// A name that does not collide with an existing project.
  String uniqueName(String base) {
    final names = projects.map((p) => p.name).toSet();
    if (!names.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base $i';
      if (!names.contains(candidate)) return candidate;
    }
  }

  /// Creates a project. Callers check [atProjectLimit] first and send the
  /// user to the Pro sheet; this method does not enforce it, so restoring a
  /// purchase never leaves a half-created project behind.
  /// An example as an unsaved scratch circuit (see [Project.scratch]).
  Project scratch(String name, SchematicDocument document) {
    final now = DateTime.now();
    return Project(
      id: _newId(),
      name: name,
      created: now,
      updated: now,
      document: document,
      scratch: true,
    );
  }

  Project create(String name, SchematicDocument document) {
    final now = DateTime.now();
    final project = Project(
      id: _newId(),
      name: uniqueName(name),
      created: now,
      updated: now,
      document: document,
    );
    projects.insert(0, project);
    _scheduleSave(immediate: true);
    notifyListeners();
    return project;
  }

  Project duplicate(Project source, String copySuffix) =>
      create('${source.name} $copySuffix', source.document);

  void rename(Project project, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == project.name) return;
    project
      ..name = trimmed
      ..updated = DateTime.now();
    _sort();
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  void delete(Project project) {
    projects.removeWhere((p) => p.id == project.id);
    _scheduleSave(immediate: true);
    notifyListeners();
  }

  /// Puts a deleted project back (the undo on the "deleted" snackbar).
  /// Returns false when the free tier's cap refused it, so the UI can say so.
  bool restore(Project project, int index) {
    if (byId(project.id) != null) return true;
    // The free tier's one-circuit cap also holds for undo: a project created
    // while the "deleted" snackbar was still up must not become a second.
    if (atProjectLimit) return false;
    projects.insert(index.clamp(0, projects.length), project);
    _scheduleSave(immediate: true);
    notifyListeners();
    return true;
  }

  /// Records a new version of a project's drawing. Called on every edit;
  /// writes are coalesced for a moment so a drag does not queue sixty files
  /// a second, and [saveNow] closes the window whenever the app backgrounds.
  void updateDocument(Project project, SchematicDocument document) {
    project
      ..document = document
      ..updated = DateTime.now();
    if (project.scratch) return;
    _sort();
    _scheduleSave();
    notifyListeners();
  }

  void _sort() => projects.sort((a, b) => b.updated.compareTo(a.updated));

  void _scheduleSave({bool immediate = false}) {
    _saveTimer?.cancel();
    if (immediate) {
      _write();
      return;
    }
    _saveTimer = Timer(const Duration(milliseconds: 350), _write);
  }

  /// Writes any pending change now and waits for it to reach the disk.
  Future<void> saveNow() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _write();
    }
    await _file.flush();
  }

  void _write() {
    // Never write before the file was read, or after it failed to read: both
    // would replace the user's saved circuits with whatever is in memory.
    if (!loaded || savingBlocked) return;
    _file.write({
      'version': 1,
      'projects': [for (final p in projects) p.toJson(), ..._unreadable],
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
