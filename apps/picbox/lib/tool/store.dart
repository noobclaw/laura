import 'package:flutter/foundation.dart';

import '../core/json_file_store.dart';
import 'engine/watermark_math.dart';

/// Free tier: every tool works fully on up to this many images per run.
const int kFreeBatchLimit = 3;

/// Persistent state: the Pro flag, per-tool remembered settings (Pro) and
/// watermark presets (Pro). One JSON document, atomic writes, never
/// destroyed on a bad read (see core/json_file_store.dart).
class PicboxStore extends ChangeNotifier {
  PicboxStore();

  final JsonFileStore _file = JsonFileStore('picbox.json');

  bool pro = false;
  bool loaded = false;

  /// Lifetime counter shown on the home hero ("已处理 N 张").
  int processedCount = 0;

  /// Remembered tool settings, keyed by tool name. Only written for Pro;
  /// the free tier starts every tool from defaults.
  final Map<String, Map<String, dynamic>> settings = {};

  /// Saved watermark presets (Pro).
  final List<WatermarkPreset> presets = [];

  Future<void> load() async {
    if (loaded) return;
    // StoreKit can replay a purchase before this read finishes; a Pro flag
    // that arrived early must survive the load and get written afterwards.
    final earlyPro = pro;
    try {
      final j = await _file.read();
      if (j != null) {
        pro = earlyPro || j['pro'] == true;
        processedCount = (j['processedCount'] as num?)?.toInt() ?? 0;
        final s = j['settings'];
        if (s is Map) {
          s.forEach((k, v) {
            if (k is String && v is Map) {
              settings[k] = Map<String, dynamic>.from(v);
            }
          });
        }
        final p = j['presets'];
        if (p is List) {
          for (final e in p) {
            if (e is Map) {
              presets.add(WatermarkPreset.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('picbox store load failed: $e');
    }
    loaded = true;
    if (earlyPro) _save();
    notifyListeners();
  }

  void _save() {
    if (!loaded) return; // never clobber the file before the first read
    _file.write({
      'version': 1,
      'pro': pro,
      'processedCount': processedCount,
      'settings': settings,
      'presets': presets.map((p) => p.toJson()).toList(),
    });
  }

  void unlockPro() {
    if (pro) return;
    pro = true;
    _save();
    notifyListeners();
  }

  void addProcessed(int n) {
    if (n <= 0) return;
    processedCount += n;
    _save();
    notifyListeners();
  }

  /// Remember [json] for [tool]. No-op on the free tier.
  void rememberSettings(String tool, Map<String, dynamic> json) {
    if (!pro) return;
    settings[tool] = json;
    _save();
  }

  Map<String, dynamic>? settingsFor(String tool) => pro ? settings[tool] : null;

  void addPreset(WatermarkPreset p) {
    presets.removeWhere((e) => e.name == p.name);
    presets.insert(0, p);
    _save();
    notifyListeners();
  }

  void removePreset(String name) {
    presets.removeWhere((e) => e.name == name);
    _save();
    notifyListeners();
  }
}

class WatermarkPreset {
  const WatermarkPreset({required this.name, required this.spec});
  final String name;
  final WatermarkSpec spec;

  Map<String, dynamic> toJson() => {'name': name, 'spec': spec.toJson()};

  static WatermarkPreset fromJson(Map<String, dynamic> j) => WatermarkPreset(
        name: j['name'] as String? ?? '',
        spec: WatermarkSpec.fromJson(
            Map<String, dynamic>.from(j['spec'] as Map? ?? const {})),
      );
}
