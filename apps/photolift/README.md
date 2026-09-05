# PhotoLift / 离线老照片修复

On-device Real-ESRGAN photo upscaler (2x / 4x + denoise). Photos never leave
the phone. See `PLAN.md` for the product plan, native-integration status and
the CI notes; `store/listing.md` for the store copy.

Layout beyond the factory shell:

- `native/photolift_core.{h,cpp}` — shared C++ tiling/inference core on ncnn.
- `android/app/src/main/cpp/` — CMake + JNI glue; `build.gradle.kts` downloads
  the prebuilt ncnn package at build time (`fetchNcnn`).
- `android/app/src/main/kotlin/.../{NcnnUpscaler,UpscaleBridge,MediaBridge}.kt`
- `ios/Runner/{PhotoLiftEngine.h,.mm,UpscaleBridge.swift,MediaBridge.swift}`;
  `scripts/fetch_ncnn_ios.sh` fetches the ncnn frameworks (run by an Xcode
  phase); `scripts/patch_ios_project.cjs` is the pbxproj edit that wired it.
- `assets/models/` — converted weights (`scripts/convert_model.py`).
- `lib/tool/` — the Flutter side (`fallback_upscaler.dart` is the labelled
  non-AI fallback used only when the native engine is missing).
- `scripts/icons.mjs` — launcher / store icon generator.

Local checks: `flutter analyze`, `flutter test` (never `flutter build` on the
dev machine — CI only).
