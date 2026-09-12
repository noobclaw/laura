// Host-side tests for photolift_tiling.h (no ncnn needed). Run with
// native/tests/run_host_tests.sh. Fixtures marked "ncnn" were produced by
// the ncnn 1.0.20260526 python wheel running an Interp layer
// (resize_type=3, scale 2/4, align_corners=0) — the very op the reference
// uses for alpha — see REFERENCE.md.
#include "../photolift_tiling.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

using namespace photolift;
using namespace photolift::tiling;

static int gFailures = 0;
#define CHECK(cond)                                                                   \
    do {                                                                              \
        if (!(cond)) {                                                                \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);      \
            gFailures++;                                                              \
        }                                                                             \
    } while (0)

// ---------------------------------------------------------------- fixtures
// ncnn Interp bicubic, w=6: rows = output index, cols = source index.
static const float kCoef4[24 * 6] = {
1.1099f,-0.1099f,0.0000f,0.0000f,0.0000f,0.0000f,1.0718f,-0.0718f,0.0000f,0.0000f,0.0000f,0.0000f,0.8955f,0.1147f,-0.0103f,0.0000f,0.0000f,0.0000f,0.6396f,0.4263f,-0.0659f,0.0000f,0.0000f,0.0000f,0.3604f,0.7495f,-0.1099f,0.0000f,0.0000f,0.0000f,0.1045f,0.9673f,-0.0718f,0.0000f,0.0000f,0.0000f,-0.0718f,0.9673f,0.1147f,-0.0103f,0.0000f,0.0000f,-0.1099f,0.7495f,0.4263f,-0.0659f,0.0000f,0.0000f,-0.0659f,0.4263f,0.7495f,-0.1099f,0.0000f,0.0000f,-0.0103f,0.1147f,0.9673f,-0.0718f,0.0000f,0.0000f,0.0000f,-0.0718f,0.9673f,0.1147f,-0.0103f,0.0000f,0.0000f,-0.1099f,0.7495f,0.4263f,-0.0659f,0.0000f,0.0000f,-0.0659f,0.4263f,0.7495f,-0.1099f,0.0000f,0.0000f,-0.0103f,0.1147f,0.9673f,-0.0718f,0.0000f,0.0000f,0.0000f,-0.0718f,0.9673f,0.1147f,-0.0103f,0.0000f,0.0000f,-0.1099f,0.7495f,0.4263f,-0.0659f,0.0000f,0.0000f,-0.0659f,0.4263f,0.7495f,-0.1099f,0.0000f,0.0000f,-0.0103f,0.1147f,0.9673f,-0.0718f,0.0000f,0.0000f,0.0000f,-0.0718f,0.9673f,0.1045f,0.0000f,0.0000f,0.0000f,-0.1099f,0.7495f,0.3604f,0.0000f,0.0000f,0.0000f,-0.0659f,0.4263f,0.6396f,0.0000f,0.0000f,0.0000f,-0.0103f,0.1147f,0.8955f,0.0000f,0.0000f,0.0000f,0.0000f,-0.0718f,1.0718f,0.0000f,0.0000f,0.0000f,0.0000f,-0.1099f,1.1099f};
static const float kCoef2[12 * 6] = {
1.1055f,-0.1055f,0.0000f,0.0000f,0.0000f,0.0000f,0.7734f,0.2617f,-0.0352f,0.0000f,0.0000f,0.0000f,0.2266f,0.8789f,-0.1055f,0.0000f,0.0000f,0.0000f,-0.1055f,0.8789f,0.2617f,-0.0352f,0.0000f,0.0000f,-0.0352f,0.2617f,0.8789f,-0.1055f,0.0000f,0.0000f,0.0000f,-0.1055f,0.8789f,0.2617f,-0.0352f,0.0000f,0.0000f,-0.0352f,0.2617f,0.8789f,-0.1055f,0.0000f,0.0000f,0.0000f,-0.1055f,0.8789f,0.2617f,-0.0352f,0.0000f,0.0000f,-0.0352f,0.2617f,0.8789f,-0.1055f,0.0000f,0.0000f,0.0000f,-0.1055f,0.8789f,0.2266f,0.0000f,0.0000f,0.0000f,-0.0352f,0.2617f,0.7734f,0.0000f,0.0000f,0.0000f,0.0000f,-0.1055f,1.1055f};
// ncnn Interp bicubic x2 of this 6x6 plane (row-major).
static const unsigned char kPlane6[36] = {
    0, 255, 30, 200, 90, 15,
    120, 60, 240, 10, 200, 77,
    90, 180, 45, 255, 5, 130,
    33, 210, 99, 0, 250, 180,
    255, 0, 128, 64, 32, 16,
    8, 40, 222, 111, 199, 73};
// Ground truth for the 2-D bicubic of kPlane6 is built at run time by
// applying the ncnn coefficient matrix (kCoef2 / kCoef4, each verified
// against the ncnn wheel in testCubicCoefficients) separably — see
// bicubicPlaneRef. An earlier revision hard-coded a 12x12 table here that
// was inconsistent with kCoef2 (off by up to 171); it was removed because
// the matrix, not a hand-recorded dump, is the authority ncnn defines.

// Separable reference resize of an n x n single-channel plane by `scale`
// using the recorded ncnn coefficient matrix `coef` (outn rows x n cols).
static std::vector<float> bicubicPlaneRef(const unsigned char* plane, int n, int scale,
                                          const float* coef) {
    const int outn = n * scale;
    std::vector<float> tmp((size_t)outn * n, 0.f);   // horizontal pass
    for (int y = 0; y < n; y++)
        for (int ox = 0; ox < outn; ox++) {
            float acc = 0.f;
            for (int s = 0; s < n; s++) acc += coef[ox * n + s] * plane[y * n + s];
            tmp[(size_t)y * outn + ox] = acc;
        }
    std::vector<float> out((size_t)outn * outn, 0.f);  // vertical pass
    for (int oy = 0; oy < outn; oy++)
        for (int ox = 0; ox < outn; ox++) {
            float acc = 0.f;
            for (int s = 0; s < n; s++) acc += coef[oy * n + s] * tmp[(size_t)s * outn + ox];
            out[(size_t)oy * outn + ox] = acc;
        }
    return out;
}

// ------------------------------------------------------------ stub network
// A shift-equivariant local 4x operator: half nearest-neighbour, half the
// mean of an 11x11 window (radius 5 < overlap), plus a sub-pixel ramp so
// the four output pixels of a source pixel differ. Reads that fall outside
// the padded tile clamp to its edge — those only matter within 5 px of the
// padded border, which the stitcher never keeps. Any real network with an
// effective receptive field inside the overlap behaves the same way.
static const int kM = 4;
static int stubInfer(void*, const float* in, int w, int h, float* out) {
    const size_t plane = (size_t)w * h;
    const int ow = w * kM, oh = h * kM;
    const size_t oplane = (size_t)ow * oh;
    for (int c = 0; c < 3; c++) {
        const float* p = in + (size_t)c * plane;
        for (int Y = 0; Y < oh; Y++) {
            const int y = Y / kM;
            for (int X = 0; X < ow; X++) {
                const int x = X / kM;
                float sum = 0.f;
                for (int dy = -5; dy <= 5; dy++) {
                    int yy = y + dy; yy = yy < 0 ? 0 : (yy >= h ? h - 1 : yy);
                    for (int dx = -5; dx <= 5; dx++) {
                        int xx = x + dx; xx = xx < 0 ? 0 : (xx >= w ? w - 1 : xx);
                        sum += p[(size_t)yy * w + xx];
                    }
                }
                const float ramp = ((X % kM) + (Y % kM)) * 0.004f;
                out[(size_t)c * oplane + (size_t)Y * ow + X] =
                    0.5f * p[(size_t)y * w + x] + 0.5f * (sum / 121.f) + ramp;
            }
        }
    }
    return 0;
}

static int failingInfer(void*, const float*, int, int, float*) { return 1; }

struct ProgressLog { int last; int total; int calls; };
static void logProgress(void* u, int done, int total) {
    ProgressLog* l = static_cast<ProgressLog*>(u);
    l->last = done; l->total = total; l->calls++;
}

// A 64x64 RGBA test image: diagonal gradient, a checker patch, a hard edge,
// and an alpha ramp with a fully transparent stripe.
static std::vector<unsigned char> makeImage(int w, int h, int channels) {
    std::vector<unsigned char> img((size_t)w * h * channels);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            unsigned char* p = &img[((size_t)y * w + x) * channels];
            p[0] = (unsigned char)((x * 255) / (w - 1));
            p[1] = (unsigned char)((y * 255) / (h - 1));
            p[2] = (unsigned char)(((x + y) * 127) / (w + h - 2) + (((x / 4 + y / 4) & 1) ? 64 : 0));
            if (x > 40 && y > 20 && y < 30) { p[0] = 10; p[1] = 250; p[2] = 10; }
            if (channels == 4) {
                p[3] = (unsigned char)((x * 200) / (w - 1) + 55);
                if (y >= 48 && y < 52) p[3] = 0;
            }
        }
    }
    return img;
}

static int maxAbsDiff(const std::vector<unsigned char>& a, const std::vector<unsigned char>& b,
                      int channels, int channel) {
    int m = 0;
    for (size_t i = (size_t)channel; i < a.size(); i += (size_t)channels) {
        const int d = std::abs((int)a[i] - (int)b[i]);
        if (d > m) m = d;
    }
    return m;
}

// ------------------------------------------------------------------- tests
static void testReflectIndex() {
    for (int n = 1; n <= 64; n = n * 3 + 1) {
        for (int i = -(n - 1); i <= 2 * (n - 1); i++) {
            int expect;
            if (n <= 1) {
                expect = 0;
            } else {
                // realesrgan_preproc.comp, verbatim formula.
                int x = std::abs(i);
                x = (n - 1) - std::abs(x - (n - 1));
                expect = x;
            }
            CHECK(reflectIndex(i, n) == expect);
        }
    }
    CHECK(reflectIndex(-1, 5) == 1);
    CHECK(reflectIndex(5, 5) == 3);
    CHECK(reflectIndex(-9, 5) == 1);   // far outside still lands inside
    CHECK(reflectIndex(3, 1) == 0);
}

static void testQuantize() {
    CHECK(quantize01(0.f) == 0);
    CHECK(quantize01(1.f) == 255);
    CHECK(quantize01(-0.3f) == 0);
    CHECK(quantize01(1.7f) == 255);
    CHECK(quantize01(127.4f / 255.f) == 127);
    CHECK(quantize01(127.6f / 255.f) == 128);
    CHECK(quantize255(254.5f) == 255);
    CHECK(quantize255(-4.f) == 0);
    CHECK(quantize255(300.f) == 255);
    CHECK(quantize255(12.49f) == 12);
}

static void testCubicCoefficients() {
    // Rebuild ncnn's 1-D interpolation matrix from cubicTap and compare.
    const struct { int scale; const float* m; } cases[] = {{4, kCoef4}, {2, kCoef2}};
    for (int ci = 0; ci < 2; ci++) {
        const int scale = cases[ci].scale;
        const int n = 6, outn = n * scale;
        for (int d = 0; d < outn; d++) {
            float row[6] = {0, 0, 0, 0, 0, 0};
            const CubicTap t = cubicTap(d, n, scale);
            for (int j = 0; j < 4; j++) row[t.idx[j]] += t.k[j];
            for (int s = 0; s < n; s++) {
                const float diff = std::fabs(row[s] - cases[ci].m[d * n + s]);
                if (diff > 2e-4f) {
                    std::fprintf(stderr, "coef mismatch scale %d d=%d s=%d got %.4f want %.4f\n",
                                 scale, d, s, row[s], cases[ci].m[d * n + s]);
                }
                CHECK(diff <= 2e-4f);
            }
        }
    }
}

static void testBicubicAlphaMatchesNcnn() {
    // 6x6 RGBA image whose alpha is kPlane6; RGB irrelevant. The alpha path
    // must equal the ncnn coefficient matrix applied separably (the taps
    // themselves are checked against the ncnn wheel in testCubicCoefficients),
    // for both scales, to <=1 (float accumulation order differs by <1 LSB).
    std::vector<unsigned char> in(36 * 4, 0);
    for (int i = 0; i < 36; i++) in[(size_t)i * 4 + 3] = kPlane6[i];
    const struct { int scale; const float* coef; } cases[] = {{4, kCoef4}, {2, kCoef2}};
    for (int ci = 0; ci < 2; ci++) {
        const int scale = cases[ci].scale, outn = 6 * scale;
        std::vector<unsigned char> out((size_t)outn * outn * 4, 0);
        bicubicAlphaRect(in.data(), 6, 6, 6 * 4, scale, 0, 0, outn, outn, out.data(), outn * 4);
        const std::vector<float> ref = bicubicPlaneRef(kPlane6, 6, scale, cases[ci].coef);
        int bad = 0, maxd = 0;
        for (int i = 0; i < outn * outn; i++) {
            const int d = std::abs((int)out[(size_t)i * 4 + 3] - (int)quantize255(ref[(size_t)i]));
            if (d > 1) bad++;
            if (d > maxd) maxd = d;
        }
        if (bad) std::fprintf(stderr, "alpha bicubic scale %d: %d px off, max %d\n", scale, bad, maxd);
        CHECK(bad == 0);
        // The rectangle form must equal the whole-image result (no seams).
        std::vector<unsigned char> part((size_t)outn * outn * 4, 0);
        const int hx = outn / 2, hy = outn / 2;
        bicubicAlphaRect(in.data(), 6, 6, 6 * 4, scale, 0, 0, hx, hy, part.data(), outn * 4);
        bicubicAlphaRect(in.data(), 6, 6, 6 * 4, scale, hx, 0, outn - hx, hy, part.data(), outn * 4);
        bicubicAlphaRect(in.data(), 6, 6, 6 * 4, scale, 0, hy, outn, outn - hy, part.data(), outn * 4);
        CHECK(maxAbsDiff(part, out, 4, 3) == 0);
    }
}

static void runStitch(int w, int h, int inCh, int outCh, int scale, int tile, int overlap,
                      const std::vector<unsigned char>& img, std::vector<unsigned char>& out,
                      ProgressLog* log = 0) {
    out.assign((size_t)(w * scale) * (h * scale) * outCh, 7);
    const int rc = processTiled(img.data(), w, h, inCh, w * inCh,
                                out.data(), outCh, w * scale * outCh,
                                kM, scale, tile, overlap, stubInfer, 0, 0,
                                log ? logProgress : 0, log);
    CHECK(rc == kDone);
}

static void testTiledEqualsUntiled() {
    const int w = 64, h = 64, overlap = 12;
    for (int inCh = 3; inCh <= 4; inCh++) {
        const std::vector<unsigned char> img = makeImage(w, h, inCh);
        for (int scale = 4; scale >= 2; scale -= 2) {
            for (int outCh = 3; outCh <= 4; outCh++) {
                std::vector<unsigned char> whole, tiled16, tiled24, tiled32;
                runStitch(w, h, inCh, outCh, scale, 64, overlap, img, whole);   // one tile
                runStitch(w, h, inCh, outCh, scale, 16, overlap, img, tiled16);
                runStitch(w, h, inCh, outCh, scale, 24, overlap, img, tiled24); // non-multiple
                runStitch(w, h, inCh, outCh, scale, 32, overlap, img, tiled32);
                for (int c = 0; c < outCh; c++) {
                    const int d16 = maxAbsDiff(whole, tiled16, outCh, c);
                    const int d24 = maxAbsDiff(whole, tiled24, outCh, c);
                    const int d32 = maxAbsDiff(whole, tiled32, outCh, c);
                    if (d16 > 1 || d24 > 1 || d32 > 1) {
                        std::fprintf(stderr, "stitch diff in=%d out=%d scale=%d ch=%d: %d %d %d\n",
                                     inCh, outCh, scale, c, d16, d24, d32);
                    }
                    CHECK(d16 <= 1);
                    CHECK(d24 <= 1);
                    CHECK(d32 <= 1);
                }
                // Every output byte was written (no sentinel 7 survives in a
                // channel that cannot legitimately be 7... alpha can't be 7
                // when opaque; check the RGBA opaque fill explicitly below).
                if (outCh == 4 && inCh == 3) {
                    int nonOpaque = 0;
                    for (size_t i = 3; i < whole.size(); i += 4) if (whole[i] != 255) nonOpaque++;
                    CHECK(nonOpaque == 0);
                }
            }
        }
    }
}

static void testAlphaPreserved() {
    const int w = 64, h = 64;
    const std::vector<unsigned char> img = makeImage(w, h, 4);
    for (int scale = 2; scale <= 4; scale += 2) {
        std::vector<unsigned char> out;
        runStitch(w, h, 4, 4, scale, 16, 12, img, out);
        const int W = w * scale, H = h * scale;
        // Whole-image bicubic of the alpha plane is the ground truth.
        std::vector<unsigned char> ref((size_t)W * H * 4, 0);
        bicubicAlphaRect(img.data(), w, h, w * 4, scale, 0, 0, W, H, ref.data(), W * 4);
        CHECK(maxAbsDiff(out, ref, 4, 3) == 0);
        // The transparent stripe stays transparent in its interior and the
        // opaque-ish ramp keeps rising left to right.
        const int ys = 50 * scale;   // centre of the y in [48,52) stripe
        CHECK(out[((size_t)ys * W + W / 2) * 4 + 3] == 0);
        const int ym = 10 * scale;
        CHECK(out[((size_t)ym * W + 2) * 4 + 3] < out[((size_t)ym * W + W - 3) * 4 + 3]);
        CHECK(out[((size_t)ym * W + W - 3) * 4 + 3] >= 250);
        // Alpha was never mixed into RGB: RGB equals the RGB-only run.
        std::vector<unsigned char> rgbOnly;
        const std::vector<unsigned char> img3 = makeImage(w, h, 3);
        runStitch(w, h, 3, 3, scale, 16, 12, img3, rgbOnly);
        for (int c = 0; c < 3; c++) {
            int m = 0;
            for (size_t i = 0; i < (size_t)W * H; i++) {
                const int d = std::abs((int)out[i * 4 + c] - (int)rgbOnly[i * 3 + c]);
                if (d > m) m = d;
            }
            CHECK(m == 0);
        }
    }
}

static void testGeometryAndProgress() {
    // Odd sizes, tiles that do not divide the image, one-pixel edge cases.
    const int sizes[][2] = {{70, 45}, {1, 1}, {33, 2}, {5, 97}};
    for (int si = 0; si < 4; si++) {
        const int w = sizes[si][0], h = sizes[si][1];
        const std::vector<unsigned char> img = makeImage(w < 2 ? 2 : w, h < 2 ? 2 : h, 3);
        std::vector<unsigned char> imgCut((size_t)w * h * 3);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                for (int c = 0; c < 3; c++)
                    imgCut[((size_t)y * w + x) * 3 + c] = img[((size_t)y * (w < 2 ? 2 : w) + x) * 3 + c];
        ProgressLog log = {0, 0, 0};
        std::vector<unsigned char> out;
        runStitch(w, h, 3, 4, 4, 32, 12, imgCut, out, &log);
        CHECK(log.total == tileCount(w, h, 32));
        CHECK(log.calls == log.total);
        CHECK(log.last == log.total);
        int nonOpaque = 0;
        for (size_t i = 3; i < out.size(); i += 4) if (out[i] != 255) nonOpaque++;
        CHECK(nonOpaque == 0);
    }
    CHECK(tileCount(64, 64, 16) == 16);
    CHECK(tileCount(65, 64, 16) == 20);
    CHECK(tileCount(0, 64, 16) == 0);
}

static void testCancelAndErrors() {
    const int w = 40, h = 40;
    const std::vector<unsigned char> img = makeImage(w, h, 3);
    std::vector<unsigned char> out((size_t)w * 4 * h * 4 * 3, 0);
    std::atomic<bool> cancel(true);
    CHECK(processTiled(img.data(), w, h, 3, w * 3, out.data(), 3, w * 4 * 3,
                       kM, 4, 16, 12, stubInfer, 0, &cancel, 0, 0) == kCancelled);
    cancel.store(false);
    CHECK(processTiled(img.data(), w, h, 3, w * 3, out.data(), 3, w * 4 * 3,
                       kM, 4, 16, 12, failingInfer, 0, &cancel, 0, 0) == kInferFailed);
    CHECK(processTiled(img.data(), w, h, 3, w * 3, out.data(), 3, w * 4 * 3,
                       kM, 3, 16, 12, stubInfer, 0, 0, 0, 0) == kBadArgs);
    CHECK(processTiled(img.data(), w, h, 2, w * 3, out.data(), 3, w * 4 * 3,
                       kM, 4, 16, 12, stubInfer, 0, 0, 0, 0) == kBadArgs);
    CHECK(processTiled(img.data(), w, h, 3, w * 3, out.data(), 3, w * 4 * 3,
                       kM, 4, 16, 12, stubInfer, 0, &cancel, 0, 0) == kDone);
}

static void testGatherReflectsAtBorder() {
    // 4x3 RGB image, gather a window that overhangs by 2 on every side.
    const int w = 4, h = 3;
    std::vector<unsigned char> img((size_t)w * h * 3);
    for (int i = 0; i < w * h; i++) { img[(size_t)i * 3] = (unsigned char)(i * 10); img[(size_t)i * 3 + 1] = 0; img[(size_t)i * 3 + 2] = 0; }
    const int tw = w + 4, th = h + 4;
    std::vector<float> dst((size_t)3 * tw * th);
    gatherTile(img.data(), w, h, 3, w * 3, -2, -2, tw, th, dst.data());
    // (-2,-2) reflects to (2,2) -> index 2*4+2=10 -> 100/255.
    CHECK(std::fabs(dst[0] - 100.f / 255.f) < 1e-6f);
    // (5,-1) -> x=5 reflects to 1, y=-1 -> 1 -> index 1*4+1=5 -> 50/255.
    CHECK(std::fabs(dst[(size_t)1 * tw + 7] - 50.f / 255.f) < 1e-6f);
    // Interior (0,0) -> index 0 -> 0.
    CHECK(dst[(size_t)2 * tw + 2] == 0.f);
    // Green/blue planes are zero.
    CHECK(dst[(size_t)tw * th + 3] == 0.f);
}

int main() {
    testReflectIndex();
    testQuantize();
    testCubicCoefficients();
    testBicubicAlphaMatchesNcnn();
    testGatherReflectsAtBorder();
    testTiledEqualsUntiled();
    testAlphaPreserved();
    testGeometryAndProgress();
    testCancelAndErrors();
    if (gFailures) {
        std::fprintf(stderr, "%d check(s) failed\n", gFailures);
        return 1;
    }
    std::printf("photolift tiling tests: all passed\n");
    return 0;
}
