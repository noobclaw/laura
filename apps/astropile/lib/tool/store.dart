import 'package:flutter/foundation.dart';

import '../core/json_file_store.dart';
import 'engine/stack.dart';
import 'models.dart';

/// Frames per stack on the free tier. Six is a real burst — enough to halve
/// the noise and to see every part of the app work — not a teaser.
const int kFreeFrameLimit = 6;

/// Frames per stack with Pro. Above ~32 the returns are small and the
/// scratch-disk footprint stops being reasonable on a phone.
const int kProFrameLimit = 32;

/// Written price, shown only until the store answers with the real one.
const String kProFallbackPrice = r'$3.99';

/// Persistent state: the Pro flag, the lifetime counter and the remembered
/// stacking settings (Pro). One JSON document, atomic writes.
class AstroStore extends ChangeNotifier {
  AstroStore();

  final JsonFileStore _file = JsonFileStore('astropile.json');

  bool pro = false;
  bool loaded = false;

  /// Lifetime number of finished stacks, shown on the home hero.
  int stackedCount = 0;

  StackMode mode = StackMode.mean;
  WorkScale scale = WorkScale.full;

  int get frameLimit => pro ? kProFrameLimit : kFreeFrameLimit;

  Future<void> load() async {
    if (loaded) return;
    var storedPro = false;
    try {
      final j = await _file.read();
      // StoreKit replays purchases at launch, and that callback can land
      // *during* the read above. Sampling the in-memory flag afterwards is
      // what keeps such a replay from being overwritten by the file — the
      // other order silently drops a restored purchase.
      final earlyPro = pro;
      if (j != null) {
        storedPro = j['pro'] == true;
        pro = earlyPro || storedPro;
        stackedCount = (j['stackedCount'] as num?)?.toInt() ?? 0;
        if (pro) {
          mode = j['mode'] == 'median' ? StackMode.median : StackMode.mean;
          scale = j['scale'] == 'half' ? WorkScale.half : WorkScale.full;
        }
      }
    } catch (e) {
      debugPrint('astropile store load failed: $e');
    }
    loaded = true;
    if (pro && !storedPro) _save();
    notifyListeners();
  }

  void _save() {
    if (!loaded) return; // never clobber the file before the first read
    _file.write({
      'version': 1,
      'pro': pro,
      'stackedCount': stackedCount,
      'mode': mode.name,
      'scale': scale.name,
    });
  }

  void unlockPro() {
    if (pro) return;
    pro = true;
    _save();
    notifyListeners();
  }

  void addStacked() {
    stackedCount++;
    _save();
    notifyListeners();
  }

  /// Median stacking is the Pro half of the split; a free user who somehow
  /// holds a median setting still gets mean, so the gate cannot be bypassed
  /// by a stale settings file.
  StackSettings get settings => StackSettings(
        mode: pro ? mode : StackMode.mean,
        scale: scale,
      );

  void setMode(StackMode m) {
    if (mode == m) return;
    mode = m;
    if (pro) _save();
    notifyListeners();
  }

  void setScale(WorkScale s) {
    if (scale == s) return;
    scale = s;
    if (pro) _save();
    notifyListeners();
  }
}
