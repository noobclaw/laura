// PhotoLift — the ncnn-independent half of the upscaling core: tile
// planning, reflect padding, input normalisation, output quantisation,
// centre-crop stitching, the 4x -> 2x box filter and the bicubic alpha path.
//
// Everything here is header-only, C++11, exception-free and has no ncnn
// dependency, so it compiles on a desktop host and is covered by
// native/tests/tiling_test.cpp (tiled == untiled, alpha preserved, bicubic
// == ncnn Interp fixtures). photolift_core.cpp adapts it to ncnn::Net.
//
// Reference (see REFERENCE.md): xinntao/Real-ESRGAN-ncnn-vulkan
// src/realesrgan.cpp + realesrgan_preproc.comp / realesrgan_postproc.comp.
//  - padding      : reflect-101 (`x = abs(x); x = (w-1) - abs(x-(w-1))`)
//  - normalise    : v / 255
//  - quantise     : floor(v * 255 + 0.5) clamped to [0, 255]
//  - stitch       : keep the un-padded centre of every tile, copy in place
//  - alpha        : not run through the network; bicubic (ncnn Interp,
//                   resize_type=3, A=-0.75, half-pixel centres) per scale
#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <vector>

namespace photolift {

/// Per-tile progress callback: `done` tiles finished out of `total`.
typedef void (*ProgressFn)(void* user, int done, int total);

namespace tiling {

enum Status {
    kDone = 0,
    kInferFailed = 1,
    kCancelled = 2,
    kBadArgs = 3,
};

/// Runs the network on one padded tile. `in` is CHW float RGB in [0,1]
/// (w x h x 3); `out` must receive CHW float RGB of (w*M) x (h*M) x 3.
/// Return 0 on success.
typedef int (*InferFn)(void* user, const float* in, int w, int h, float* out);

/// Reflect-101 index (mirror without repeating the edge sample) — the same
/// mapping realesrgan_preproc.comp applies, generalised to any distance.
/// A 1-pixel axis maps every index to 0.
inline int reflectIndex(int i, int n) {
    if (n <= 1) return 0;
    const int period = 2 * (n - 1);
    i = i < 0 ? -i : i;
    i %= period;
    if (i >= n) i = period - i;
    return i;
}

/// realesrgan_postproc.comp: v * 255 + 0.5, floor, clamp to [0, 255].
inline unsigned char quantize01(float v01) {
    float v = std::floor(v01 * 255.f + 0.5f);
    if (v < 0.f) v = 0.f;
    if (v > 255.f) v = 255.f;
    return (unsigned char)v;
}

/// Same rounding for a value already in 0..255 units (the alpha path).
inline unsigned char quantize255(float v) {
    v = std::floor(v + 0.5f);
    if (v < 0.f) v = 0.f;
    if (v > 255.f) v = 255.f;
    return (unsigned char)v;
}

inline int tileCount(int w, int h, int tileSize) {
    if (w <= 0 || h <= 0 || tileSize <= 0) return 0;
    const int xt = (w + tileSize - 1) / tileSize;
    const int yt = (h + tileSize - 1) / tileSize;
    return xt * yt;
}

/// Reads the padded window [tx0, tx0+tw) x [ty0, ty0+th) of an 8-bit RGB /
/// RGBA image into CHW float RGB in [0,1]; coordinates outside the image
/// are reflected (reflect-101). `dst` holds 3 * tw * th floats.
inline void gatherTile(const unsigned char* in, int w, int h, int inChannels, int inStride,
                       int tx0, int ty0, int tw, int th, float* dst) {
    const float norm = 1.f / 255.f;
    const size_t plane = (size_t)tw * th;
    std::vector<int> xs((size_t)tw);
    for (int x = 0; x < tw; x++) xs[(size_t)x] = reflectIndex(tx0 + x, w);
    for (int y = 0; y < th; y++) {
        const int sy = reflectIndex(ty0 + y, h);
        const unsigned char* row = in + (size_t)sy * inStride;
        float* d0 = dst + (size_t)y * tw;
        float* d1 = d0 + plane;
        float* d2 = d1 + plane;
        for (int x = 0; x < tw; x++) {
            const unsigned char* p = row + (size_t)xs[(size_t)x] * inChannels;
            d0[x] = p[0] * norm;
            d1[x] = p[1] * norm;
            d2[x] = p[2] * norm;
        }
    }
}

/// One output sample of a bicubic resize: four source indices (clamped to
/// the axis) and their weights. Matches ncnn's Interp layer with
/// resize_type=3 (bicubic, A = -0.75), align_corners=false: the sample
/// centre is (d + 0.5) / scale - 0.5, taps outside the axis fold onto the
/// edge sample. Verified against ncnn in native/tests/tiling_test.cpp.
struct CubicTap {
    int idx[4];
    float k[4];
};

inline void cubicWeights(float t, float* k) {
    const float A = -0.75f;
    const float x0 = t + 1.f;
    const float x1 = t;
    const float x2 = 1.f - t;
    const float x3 = x2 + 1.f;
    k[0] = ((A * x0 - 5.f * A) * x0 + 8.f * A) * x0 - 4.f * A;
    k[1] = ((A + 2.f) * x1 - (A + 3.f)) * x1 * x1 + 1.f;
    k[2] = ((A + 2.f) * x2 - (A + 3.f)) * x2 * x2 + 1.f;
    k[3] = ((A * x3 - 5.f * A) * x3 + 8.f * A) * x3 - 4.f * A;
}

inline CubicTap cubicTap(int d, int n, int scale) {
    CubicTap t;
    const float fx = (d + 0.5f) / (float)scale - 0.5f;
    const int sx = (int)std::floor(fx);
    cubicWeights(fx - (float)sx, t.k);
    for (int j = 0; j < 4; j++) {
        int i = sx - 1 + j;
        if (i < 0) i = 0;
        if (i > n - 1) i = n - 1;
        t.idx[j] = i;
    }
    return t;
}

/// Bicubic-resizes the alpha plane (channel 3 of an RGBA image) by `scale`
/// and writes the output rectangle [ox0, ox0+ow) x [oy0, oy0+oh) (output
/// coordinates) into channel 3 of `out`. Sampling uses whole-image
/// coordinates, so tiles never introduce seams in alpha.
inline void bicubicAlphaRect(const unsigned char* in, int w, int h, int inStride, int scale,
                             int ox0, int oy0, int ow, int oh,
                             unsigned char* out, int outStride) {
    if (ow <= 0 || oh <= 0) return;
    std::vector<CubicTap> xt((size_t)ow);
    for (int x = 0; x < ow; x++) xt[(size_t)x] = cubicTap(ox0 + x, w, scale);
    for (int y = 0; y < oh; y++) {
        const CubicTap ty = cubicTap(oy0 + y, h, scale);
        const unsigned char* rows[4];
        for (int i = 0; i < 4; i++) rows[i] = in + (size_t)ty.idx[i] * inStride + 3;
        unsigned char* d = out + (size_t)(oy0 + y) * outStride + (size_t)ox0 * 4 + 3;
        for (int x = 0; x < ow; x++) {
            const CubicTap& tx = xt[(size_t)x];
            float acc = 0.f;
            for (int i = 0; i < 4; i++) {
                float rowAcc = 0.f;
                for (int j = 0; j < 4; j++) rowAcc += tx.k[j] * rows[i][(size_t)tx.idx[j] * 4];
                acc += ty.k[i] * rowAcc;
            }
            d[(size_t)x * 4] = quantize255(acc);
        }
    }
}

/// Writes the un-padded centre of one network output tile into `out`.
/// `outTile` is CHW float RGB of otw x oth (the padded tile times M);
/// [x0,x1) x [y0,y1) is the tile's un-padded region in input pixels.
/// scale == M copies 1:1; scale == M/2 averages 2x2 blocks in float before
/// quantising (the 4x network serving a 2x request). RGB only — alpha is
/// handled by bicubicAlphaRect / fillAlphaRect.
inline void scatterTile(const float* outTile, int otw, int oth, int M, int overlap,
                        int x0, int y0, int x1, int y1, int scale,
                        unsigned char* out, int outChannels, int outStride) {
    const size_t plane = (size_t)otw * oth;
    const int down = M / scale;  // 1 or 2
    const int ow = (x1 - x0) * M / down;
    const int oh = (y1 - y0) * M / down;
    const int srcX = overlap * M;
    const int srcY = overlap * M;
    const float inv = 1.f / (float)(down * down);
    for (int y = 0; y < oh; y++) {
        unsigned char* d = out + (size_t)(y0 * scale + y) * outStride + (size_t)(x0 * scale) * outChannels;
        for (int x = 0; x < ow; x++) {
            for (int c = 0; c < 3; c++) {
                const float* p = outTile + (size_t)c * plane + (size_t)(srcY + y * down) * otw + srcX + x * down;
                float s = 0.f;
                for (int dy = 0; dy < down; dy++)
                    for (int dx = 0; dx < down; dx++) s += p[(size_t)dy * otw + dx];
                d[c] = quantize01(s * inv);
            }
            d += outChannels;
        }
    }
}

/// Opaque alpha for RGBA output when the input had no alpha channel.
inline void fillAlphaRect(unsigned char* out, int outStride, int ox0, int oy0, int ow, int oh) {
    for (int y = 0; y < oh; y++) {
        unsigned char* d = out + (size_t)(oy0 + y) * outStride + (size_t)ox0 * 4 + 3;
        for (int x = 0; x < ow; x++) d[(size_t)x * 4] = 255;
    }
}

/// The whole tiled pipeline. Tiles are visited rows-outer / columns-inner;
/// every tile is padded by `overlap` on all four sides (reflected at the
/// image border), run through `infer` and only its centre is kept. Returns
/// a Status. `cancel` (optional) is polled before every tile.
inline int processTiled(const unsigned char* in, int w, int h, int inChannels, int inStride,
                        unsigned char* out, int outChannels, int outStride,
                        int M, int scale, int tileSize, int overlap,
                        InferFn infer, void* inferUser,
                        const std::atomic<bool>* cancel,
                        ProgressFn progress, void* progressUser) {
    if (!in || !out || w <= 0 || h <= 0 || tileSize <= 0 || overlap < 0) return kBadArgs;
    if ((inChannels != 3 && inChannels != 4) || (outChannels != 3 && outChannels != 4)) return kBadArgs;
    if (scale != M && scale * 2 != M) return kBadArgs;
    if (!infer) return kBadArgs;

    const int xTiles = (w + tileSize - 1) / tileSize;
    const int yTiles = (h + tileSize - 1) / tileSize;
    const int total = xTiles * yTiles;
    const int maxIn = tileSize + 2 * overlap;
    std::vector<float> inBuf((size_t)3 * maxIn * maxIn);
    std::vector<float> outBuf((size_t)3 * maxIn * M * maxIn * M);
    int done = 0;

    for (int yi = 0; yi < yTiles; yi++) {
        for (int xi = 0; xi < xTiles; xi++) {
            if (cancel && cancel->load()) return kCancelled;

            const int x0 = xi * tileSize;
            const int y0 = yi * tileSize;
            const int x1 = std::min(x0 + tileSize, w);
            const int y1 = std::min(y0 + tileSize, h);
            const int tw = (x1 - x0) + 2 * overlap;
            const int th = (y1 - y0) + 2 * overlap;

            gatherTile(in, w, h, inChannels, inStride, x0 - overlap, y0 - overlap, tw, th, inBuf.data());
            if (infer(inferUser, inBuf.data(), tw, th, outBuf.data()) != 0) return kInferFailed;
            scatterTile(outBuf.data(), tw * M, th * M, M, overlap, x0, y0, x1, y1, scale,
                        out, outChannels, outStride);

            if (outChannels == 4) {
                const int ox0 = x0 * scale, oy0 = y0 * scale;
                const int ow = (x1 - x0) * scale, oh = (y1 - y0) * scale;
                if (inChannels == 4) {
                    bicubicAlphaRect(in, w, h, inStride, scale, ox0, oy0, ow, oh, out, outStride);
                } else {
                    fillAlphaRect(out, outStride, ox0, oy0, ow, oh);
                }
            }

            done++;
            if (progress) progress(progressUser, done, total);
        }
    }
    return kDone;
}

}  // namespace tiling
}  // namespace photolift
