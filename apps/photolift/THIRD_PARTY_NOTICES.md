# Third-party notices

PhotoLift bundles the following open-source components. Each keeps its own
license; none of them is modified except as noted.

## Real-ESRGAN — model weights (`assets/models/*.param`, `*.bin`)
- Source: https://github.com/xinntao/Real-ESRGAN (release v0.2.5.0,
  `realesr-general-x4v3.pth` and `realesr-general-wdn-x4v3.pth`)
- License: BSD 3-Clause, Copyright (c) 2021 Xintao Wang
- Modification: converted to ncnn format with pnnx (`scripts/convert_model.py`);
  `general-x4v3-dn05` is a 50/50 weight-space blend of the two originals, the
  same interpolation Real-ESRGAN performs for `--denoise_strength 0.5`.

## ncnn — inference runtime (downloaded at build time, not committed)
- Source: https://github.com/Tencent/ncnn (release 20260526)
- License: BSD 3-Clause, Copyright (C) 2017 THL A29 Limited, a Tencent company
- Bundled with it: glslang (BSD/Apache-2.0/MIT, Android Vulkan build) and
  LLVM OpenMP runtime (Apache-2.0 with LLVM exception, iOS build).

## Reference implementations consulted (no code copied)
- Real-ESRGAN-ncnn-vulkan (BSD-3): tiling / padding approach.
- Final2x (BSD-3): target-scale vs model-scale handling.
- upscayl (GPL-3): user-interface conventions only.

## Flutter packages
See `pubspec.yaml`; all are BSD-3 or MIT licensed (path_provider, image,
share_plus, in_app_purchase, cupertino_icons).
