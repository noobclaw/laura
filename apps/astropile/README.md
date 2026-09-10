# AstroPile / 星野叠加

Offline astrophotography stacker for phones: align a burst of night-sky shots
onto one reference frame, combine them, and — the part the competitors do not
do — **report frame by frame whether it lined up and why it did not**.

Everything runs on the device. The app declares no network permission.

- What it is, why it exists, and the whole engineering rationale: [PLAN.md](PLAN.md)
- Store copy (中文 / English) and pricing: [store/listing.md](store/listing.md)
- The launcher icon is generated, not drawn by hand: `node store/make_icons.mjs`

## Layout

```
lib/tool/engine/    the parts with no UI in them, all unit-tested
  stars.dart        run-length connected components → sub-pixel star centroids
  asterism.dart     triangle invariants + RANSAC → frame-to-frame transform
  transform.dart    2D similarity, closed-form least squares, and its inverse
  warp.dart         bilinear inverse resampling, box downsample
  stack.dart        band-wise mean / median combine, per-row coverage
  stretch.dart      black point + midtones transfer function + saturation
  pipeline.dart     isolate orchestration, progress, cancellation
  picker.dart       system photo picker + EXIF facts
  output.dart       scratch directories, save to Photos, share
lib/tool/ui/        home, frame list, run, result, per-frame report
test/               engine maths and the frame-list widget
```

## Building

Never run `flutter build` on the dev machine (see `PIPELINE.md`); packaging
goes through CI:

```
gh workflow run build-app.yml -R noobclaw/laura --ref main -f app=apps/astropile
```

Local checks:

```
flutter analyze && flutter test
```

## Credits

The asterism-matching approach follows the published design of
[astroalign](https://github.com/quatrope/astroalign) (MIT, © 2016 Martin
Beroiz). This is an independent Dart implementation; no code or resource from
that project is copied here. The star detector is our own — astroalign's
depends on SEP, which is neither Dart nor permissively licensed.
