import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import 'json_file_store.dart';

/// Asks for a store rating at the right moment and never nags.
///
/// PIPELINE.md, ASO 与自然增长标准 (G8b) item 7: the only durable source of
/// ratings is the native prompt, fired after the user has actually got value
/// out of the app — the THIRD completed core action — and never more than once
/// every 90 days. The OS decides whether to actually show anything (Apple caps
/// it at three prompts a year per app), so a call that shows nothing is fine.
///
/// Each app calls [noteCoreAction] from the one place its core action
/// completes (a stack finished, a PDF exported, a review session done, …) and
/// names that event in its PLAN.md. Nothing else in the app should touch this.
///
/// State lives in `review.json` next to the app's other JSON stores, so it
/// survives updates and is wiped with the app. No network, no analytics.
class ReviewPrompt {
  ReviewPrompt._();

  static final JsonFileStore _store = JsonFileStore('review.json');
  static const int _actionsBeforeAsk = 3;
  static const Duration _cooldown = Duration(days: 90);

  /// Testing seam: swap in a fake so widget tests do not touch the platform.
  @visibleForTesting
  static Future<void> Function()? requestOverride;

  /// Record one completed core action and ask for a review if it is time.
  ///
  /// Safe to call from anywhere on the UI isolate; it never throws (a store
  /// or platform failure just means no prompt this time).
  static Future<void> noteCoreAction() async {
    try {
      final raw = await _store.read() ?? const <String, dynamic>{};
      final count = (raw['count'] as num?)?.toInt() ?? 0;
      final lastAskMs = (raw['lastAskMs'] as num?)?.toInt();
      final now = DateTime.now();
      final next = count + 1;

      final coolingDown = lastAskMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastAskMs)) <
              _cooldown;
      final due = next >= _actionsBeforeAsk && !coolingDown;

      await _store.write({
        'count': due ? 0 : next,
        'lastAskMs': due ? now.millisecondsSinceEpoch : lastAskMs,
        'v': 1,
      });

      if (!due) return;
      final request = requestOverride;
      if (request != null) {
        await request();
        return;
      }
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (e) {
      debugPrint('review prompt skipped: $e');
    }
  }
}
