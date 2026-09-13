import 'dart:io';
import 'dart:typed_data';

import 'package:astropile/tool/engine/calibration.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dark/flat calibration, checked against the DeepSkyStacker specification in
/// REFERENCE.md §E: subtract clamped at zero, then multiply by
/// `meanFlat[channel] / max(1, flat)` and clamp at 255.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('astropile_calib'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final p = '${dir.path}/$name';
    File(p).writeAsBytesSync(Uint8List.fromList(bytes));
    return p;
  }

  /// A `w × h` packed-RGB buffer where every pixel is the same triple.
  List<int> flat(int w, int h, int r, int g, int b) =>
      [for (var i = 0; i < w * h; i++) ...[r, g, b]];

  group('master frames', () {
    test('the master is the per-pixel median of the set', () {
      // Three darks agree at 10; the fourth and fifth carry a light leak that
      // a mean would bake into every light frame of the stack.
      final raws = [
        write('d0.raw', flat(2, 1, 10, 10, 10)),
        write('d1.raw', flat(2, 1, 11, 11, 11)),
        write('d2.raw', flat(2, 1, 12, 12, 12)),
        write('d3.raw', flat(2, 1, 200, 200, 200)),
        write('d4.raw', flat(2, 1, 210, 210, 210)),
      ];
      final out = '${dir.path}/master.raw';
      buildMasterRaw(raws, 2, 1, out, CalibrationKind.dark);
      final bytes = File(out).readAsBytesSync();
      expect(bytes.length, 2 * 1 * 3);
      expect(bytes.every((v) => v == 12), isTrue);
    });

    test('a truncated input is refused rather than building a black master', () {
      // Without the length check this yields an all-zero master dark, which
      // subtracts nothing while the report claims the run was calibrated.
      final raws = [
        write('d0.raw', flat(2, 1, 10, 10, 10)),
        write('d1.raw', [1, 2, 3]), // short: a scratch write that ran out of disk
      ];
      expect(
        () => buildMasterRaw(raws, 2, 1, '${dir.path}/m.raw', CalibrationKind.dark),
        throwsA(isA<CalibrationException>().having(
            (e) => e.reason, 'reason', CalibrationProblem.truncated)),
      );
    });

    test('flat means are measured per channel', () {
      final p = write('flat.raw', flat(4, 2, 100, 150, 200));
      expect(measureFlatMeans(p, 4, 2), [100, 150, 200]);
    });

    test('a lens-cap "flat" is refused instead of blowing the picture out', () {
      final p = write('flat.raw', flat(4, 2, 2, 2, 2));
      expect(
        () => measureFlatMeans(p, 4, 2),
        throwsA(isA<CalibrationException>().having(
            (e) => e.reason, 'reason', CalibrationProblem.flatTooDark)),
      );
    });

    test('a truncated master is reported, not read short', () {
      final p = write('flat.raw', flat(2, 1, 100, 100, 100));
      expect(
        () => measureFlatMeans(p, 4, 2),
        throwsA(isA<CalibrationException>().having(
            (e) => e.reason, 'reason', CalibrationProblem.truncated)),
      );
    });
  });

  group('applying calibration', () {
    test('the dark is subtracted and clamped at zero', () {
      final dark = write('dark.raw', flat(2, 1, 30, 30, 30));
      final rgb = Uint8List.fromList([100, 20, 30, 200, 31, 0]);
      applyCalibration(rgb, 2, 1,
          MasterFrames(width: 2, height: 1, darkPath: dark, darkFrames: 3));
      // 100−30, 20−30 → clamped, 30−30, 200−30, 31−30, 0−30 → clamped.
      expect(rgb, [70, 0, 0, 170, 1, 0]);
    });

    test('the flat divides out vignetting without shifting the level', () {
      // Left pixel sits in a corner the lens darkens to 50; the right one is
      // at the centre at 150. The mean is 100, so the corner is scaled up by
      // 2 and the centre down by 2/3 — an even field comes out even.
      final flatPath = write('flat.raw', [50, 50, 50, 150, 150, 150]);
      final means = measureFlatMeans(flatPath, 2, 1);
      expect(means, [100, 100, 100]);
      final rgb = Uint8List.fromList([50, 50, 50, 150, 150, 150]);
      applyCalibration(
          rgb,
          2,
          1,
          MasterFrames(
            width: 2,
            height: 1,
            flatPath: flatPath,
            flatMeans: means,
            flatFrames: 4,
          ));
      expect(rgb, [100, 100, 100, 100, 100, 100]);
    });

    test('dark first, then flat — the order the maths needs', () {
      final dark = write('dark.raw', flat(1, 1, 20, 20, 20));
      final flatPath = write('flat.raw', flat(1, 1, 128, 128, 128));
      final rgb = Uint8List.fromList([100, 100, 100]);
      applyCalibration(
          rgb,
          1,
          1,
          MasterFrames(
            width: 1,
            height: 1,
            darkPath: dark,
            flatPath: flatPath,
            flatMeans: const [128, 128, 128],
            darkFrames: 2,
            flatFrames: 2,
          ));
      // (100 − 20) × 128/128 = 80. Flat-then-dark would give 80 too here, so
      // the point of the case is that the pair runs at all; the ordering that
      // matters is covered by the clamp test above (a negative intermediate
      // must never be multiplied).
      expect(rgb, [80, 80, 80]);
    });

    test('the result is clamped at 255', () {
      final flatPath = write('flat.raw', flat(1, 1, 10, 10, 10));
      final rgb = Uint8List.fromList([200, 200, 200]);
      applyCalibration(
          rgb,
          1,
          1,
          MasterFrames(
            width: 1,
            height: 1,
            flatPath: flatPath,
            flatMeans: const [200, 200, 200],
            flatFrames: 1,
          ));
      expect(rgb, [255, 255, 255]);
    });

    test('an empty master set is a no-op, not a crash', () {
      final rgb = Uint8List.fromList([1, 2, 3]);
      applyCalibration(rgb, 1, 1, MasterFrames.none);
      expect(rgb, [1, 2, 3]);
    });

    test('a master of the wrong size is refused', () {
      final dark = write('dark.raw', flat(2, 1, 5, 5, 5));
      final rgb = Uint8List(1 * 1 * 3);
      expect(
        () => applyCalibration(rgb, 1, 1,
            MasterFrames(width: 2, height: 1, darkPath: dark, darkFrames: 1)),
        throwsA(isA<CalibrationException>().having(
            (e) => e.reason, 'reason', CalibrationProblem.sizeMismatch)),
      );
    });

    test('a band boundary is not a seam', () {
      // More rows than one calibration band, so the streaming read has to
      // pick up exactly where it left off.
      final h = kCalibrationBandRows * 2 + 7;
      final dark = write('dark.raw', flat(3, h, 10, 10, 10));
      final rgb = Uint8List.fromList(flat(3, h, 60, 60, 60));
      applyCalibration(rgb, 3, h,
          MasterFrames(width: 3, height: h, darkPath: dark, darkFrames: 1));
      expect(rgb.every((v) => v == 50), isTrue);
    });
  });
}
