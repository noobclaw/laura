import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/main.dart';
import 'package:orbit/tool/align_screen.dart';
import 'package:orbit/tool/app_theme.dart';
import 'package:orbit/tool/catalog.dart';
import 'package:orbit/tool/models.dart';
import 'package:orbit/tool/pass_detail_screen.dart';
import 'package:orbit/tool/passes.dart';
import 'package:orbit/tool/sensors.dart';
import 'package:orbit/tool/store.dart';

/// The compass and accelerometer channels have no implementation in the test
/// harness; without stubs every sensor screen fails on a MissingPluginException
/// that says nothing about the widget under test.
void _stubSensorChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'hemanthraj/flutter_compass',
    'dev.fluttercommunity.plus/sensors/method',
    'dev.fluttercommunity.plus/sensors/accelerometer',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
  }
}

/// A store populated straight from the bundled snapshot, with no plugin calls.
OrbitStore _storeWithPasses() {
  final store = OrbitStore()
    ..loaded = true
    ..site = const ObserverSite(latitude: 39.9042, longitude: 116.4074);
  store.catalog =
      SatelliteCatalog.parse(File('assets/tle/visual.txt').readAsStringSync());
  store.passes = searchPasses(
    store.catalog.where((e) => e.featured).toList(),
    PassQuery(
      site: store.site!,
      startUtc: DateTime.now().toUtc(),
      window: const Duration(days: 3),
      visibleOnly: false,
      maxResults: 20,
    ),
  );
  return store;
}

void main() {
  setUp(_stubSensorChannels);

  testWidgets('app boots and renders the shell chrome', (tester) async {
    await tester.pumpWidget(const ShellApp());
    // path_provider has no responder in the test harness, so the settings read
    // fails and the store falls back to its empty state — which is exactly the
    // first-run path. The shell chrome renders regardless, which is what a
    // smoke test needs to confirm.
    await tester.pump();

    expect(find.byType(ShellApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // Tear the tree down so the hero's one-second ticker is cancelled before
    // the test completes.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both brightnesses produce a usable theme', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = buildOrbitTheme(brightness);
      expect(theme.colorScheme.brightness, brightness);
      expect(theme.cardTheme.elevation, 0);
    }
    // Dark mode must be its own palette, not the light one dimmed.
    expect(
      buildOrbitTheme(Brightness.dark).colorScheme.surface,
      isNot(buildOrbitTheme(Brightness.light).colorScheme.surface),
    );
  });

  // Regression guard: the alignment screen once put a `CrossAxisAlignment
  // .stretch` Row directly inside a scroll view, which hands its children an
  // unbounded height and throws in layout — the app's signature screen would
  // have failed to open on every device.
  testWidgets('alignment screen lays out inside a scroll view', (tester) async {
    final store = _storeWithPasses();
    expect(store.passes, isNotEmpty);

    await tester.pumpWidget(MaterialApp(
      theme: buildOrbitTheme(Brightness.dark),
      home: AlignScreen(
        pass: store.passes.first,
        store: store,
        sensors: SensorHub(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(AlignScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pass detail renders its dome and tables', (tester) async {
    final store = _storeWithPasses();
    await tester.pumpWidget(MaterialApp(
      theme: buildOrbitTheme(Brightness.light),
      home: PassDetailScreen(
        pass: store.passes.first,
        store: store,
        onAlign: (_) {},
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });
}
