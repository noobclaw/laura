import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/tool/engine/resize_math.dart';

void main() {
  group('percent', () {
    test('rounds to nearest, keeps aspect', () {
      final r = computeResize(4000, 3000, const ResizeSpec(mode: ResizeMode.percent, percent: 33));
      expect(r, (width: 1320, height: 990));
    });
    test('does not upscale unless allowed', () {
      expect(computeResize(100, 50, const ResizeSpec(mode: ResizeMode.percent, percent: 200)),
          (width: 100, height: 50));
      expect(
          computeResize(100, 50,
              const ResizeSpec(mode: ResizeMode.percent, percent: 200, allowUpscale: true)),
          (width: 200, height: 100));
    });
    test('never returns zero', () {
      expect(computeResize(3, 3, const ResizeSpec(mode: ResizeMode.percent, percent: 1)),
          (width: 1, height: 1));
    });
  });

  group('longest side', () {
    test('landscape and portrait', () {
      expect(computeResize(4000, 3000, const ResizeSpec(mode: ResizeMode.longestSide, longest: 1920)),
          (width: 1920, height: 1440));
      expect(computeResize(3000, 4000, const ResizeSpec(mode: ResizeMode.longestSide, longest: 1920)),
          (width: 1440, height: 1920));
    });
    test('small image untouched', () {
      expect(computeResize(800, 600, const ResizeSpec(mode: ResizeMode.longestSide, longest: 1920)),
          (width: 800, height: 600));
    });
  });

  group('pixels', () {
    test('single side follows aspect', () {
      expect(computeResize(4000, 3000, const ResizeSpec(mode: ResizeMode.pixels, width: 1000)),
          (width: 1000, height: 750));
      expect(computeResize(4000, 3000, const ResizeSpec(mode: ResizeMode.pixels, height: 300)),
          (width: 400, height: 300));
    });
    test('both sides with aspect = fit inside box', () {
      expect(computeResize(4000, 3000, const ResizeSpec(mode: ResizeMode.pixels, width: 1000, height: 1000)),
          (width: 1000, height: 750));
    });
    test('both sides without aspect = stretch verbatim', () {
      expect(
          computeResize(4000, 3000,
              const ResizeSpec(mode: ResizeMode.pixels, width: 500, height: 500, keepAspect: false)),
          (width: 500, height: 500));
    });
    test('nothing given = unchanged', () {
      expect(computeResize(40, 30, const ResizeSpec(mode: ResizeMode.pixels)), (width: 40, height: 30));
    });
  });

  test('spec round-trips through json', () {
    const s = ResizeSpec(mode: ResizeMode.pixels, width: 12, height: null, keepAspect: false, allowUpscale: true);
    final back = ResizeSpec.fromJson(s.toJson());
    expect(back.mode, s.mode);
    expect(back.width, 12);
    expect(back.height, isNull);
    expect(back.keepAspect, isFalse);
    expect(back.allowUpscale, isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(12), '12 B');
    expect(formatBytes(480 * 1024), '480 KB');
    expect(formatBytes((1.25 * 1024 * 1024).round()), '1.25 MB');
    expect(formatBytes(12 * 1024 * 1024), '12.0 MB');
  });
}
