import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Fires when "today" changes: at local midnight while the app is open, and
/// when the app returns to the foreground on a different calendar day than
/// it left. Also fires on a time-zone change, since that moves midnight.
///
/// Every factory app that shows something dated — cards due today, days
/// until an event, today's sunrise — computed the date once per build and
/// then showed yesterday's answer to anyone who left it open overnight
/// (2026-09-02 audit, three apps). Listen to this and recompute.
///
/// Create one per app, `start()` it after `runApp`, and rebuild date-bound
/// widgets with `ListenableBuilder(listenable: dayChange, …)`.
class DayChangeNotifier extends ChangeNotifier with WidgetsBindingObserver {
  DayChangeNotifier();

  Timer? _midnight;
  DateTime _lastSeenDay = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The local calendar day this notifier last observed.
  DateTime get today => _lastSeenDay;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _armMidnight();
  }

  /// `flutter test` sets FLUTTER_TEST; a real timer that fires at midnight
  /// would otherwise fail every widget test with "pending timer". The
  /// foreground-resume path still works under test, which is the one that
  /// can be exercised there anyway.
  static final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

  void _armMidnight() {
    _midnight?.cancel();
    if (_underTest) return;
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    // +1s so DateTime.now() is unambiguously on the new day when we fire.
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _check();
      _armMidnight();
    });
  }

  void _check() {
    final now = _today();
    if (now != _lastSeenDay) {
      _lastSeenDay = now;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The device may also have slept through midnight; re-arm the timer
      // from the real clock rather than trusting the one set yesterday.
      _check();
      _armMidnight();
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _check();

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
