// See photolift_core.h for the contract. Kept C++11 and exception-free.
#include "photolift_core.h"

#include <algorithm>
#include <cstring>
#include <vector>

#include "cpu.h"
#if NCNN_VULKAN
#include "gpu.h"
#endif

namespace photolift {

namespace {

#if NCNN_VULKAN
// ncnn's Vulkan instance is process-wide; create it lazily on the first
// engine that wants the GPU and keep it for the life of the process. Tearing
// it down and re-creating it per job costs more than it saves.
bool gVulkanTried = false;
bool gVulkanReady = false;

bool ensureVulkan() {
    if (!gVulkanTried) {
        gVulkanTried = true;
        int rc = ncnn::create_gpu_instance();
        gVulkanReady = (rc == 0) && ncnn::get_gpu_count() > 0;
    }
    return gVulkanReady;
}
#endif

inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

}  // namespace

int tileCount(int w, int h, int tileSize) {
    if (w <= 0 || h <= 0 || tileSize <= 0) return 0;
    const int xt = (w + tileSize - 1) / tileSize;
    const int yt = (h + tileSize - 1) / tileSize;
    return xt * yt;
}

Engine::Engine() : cancelFlag(false), loaded_(false), gpu_(false), modelScale_(4) {}


Engine::~Engine() {
    // ncnn::Net releases its pipelines in its own destructor; the Vulkan
    // instance stays alive for the next engine.
}

void Engine::configureOptions(bool preferGpu) {
    ncnn::Option& opt = net_.opt;
    opt.num_threads = std::max(1, ncnn::get_big_cpu_count());
    // Same numeric profile Real-ESRGAN-ncnn-vulkan ships with: fp16 storage
    // and packing for speed, fp32 arithmetic to keep colours faithful.
    opt.use_fp16_packed = true;
    opt.use_fp16_storage = true;
    opt.use_fp16_arithmetic = false;
    opt.use_int8_storage = false;
    opt.use_int8_arithmetic = false;
    opt.use_packing_layout = true;
    gpu_ = false;
#if NCNN_VULKAN
    if (preferGpu && ensureVulkan()) {
        opt.use_vulkan_compute = true;
        net_.set_vulkan_device(ncnn::get_default_gpu_index());
        gpu_ = true;
    } else {
        opt.use_vulkan_compute = false;
    }
#else
    (void)preferGpu;
#endif
}

int Engine::finishLoad(bool preferGpu, int modelScale) {
    (void)preferGpu;
    modelScale_ = modelScale;
    const std::vector<const char*>& ins = net_.input_names();
    const std::vector<const char*>& outs = net_.output_names();
    if (ins.empty() || outs.empty()) return kErrNoBlobs;
    inputName_ = ins[0];
    outputName_ = outs[0];
    loaded_ = true;
    return kOk;
}

int Engine::loadFromFiles(const char* paramPath, const char* binPath, bool preferGpu, int modelScale) {
    loaded_ = false;
    configureOptions(preferGpu);
    if (net_.load_param(paramPath) != 0) return kErrParam;
    if (net_.load_model(binPath) != 0) return kErrBin;
    return finishLoad(preferGpu, modelScale);
}

#if defined(__ANDROID__)
int Engine::loadFromAssets(AAssetManager* mgr, const char* paramAsset, const char* binAsset,
                           bool preferGpu, int modelScale) {
    loaded_ = false;
    configureOptions(preferGpu);
    if (net_.load_param(mgr, paramAsset) != 0) return kErrParam;
    if (net_.load_model(mgr, binAsset) != 0) return kErrBin;
    return finishLoad(preferGpu, modelScale);
}
#endif

int Engine::process(const unsigned char* in, int w, int h, int inChannels, int inStride,
                    unsigned char* out, int outChannels, int outStride,
                    int scale, int tileSize, int overlap,
                    ProgressFn progress, void* user) {
    if (!loaded_) return kErrNotLoaded;
    if (!in || !out || w <= 0 || h <= 0) return kErrBadArgs;
    if ((inChannels != 3 && inChannels != 4) || (outChannels != 3 && outChannels != 4)) return kErrBadArgs;
    if (scale != 2 && scale != 4) return kErrBadArgs;
    if (modelScale_ != 4) return kErrBadArgs;
    tileSize = clampi(tileSize, 32, 1024);
    overlap = clampi(overlap, 0, 64);

    const int inType = inChannels == 4 ? ncnn::Mat::PIXEL_RGBA2RGB : ncnn::Mat::PIXEL_RGB;
    const int M = modelScale_;                 // network scale (4)
    const int down = M / scale;                // 1 for 4x output, 2 for 2x output
    const int xTiles = (w + tileSize - 1) / tileSize;
    const int yTiles = (h + tileSize - 1) / tileSize;
    const int total = xTiles * yTiles;
    int done = 0;

    static const float kNorm[3] = {1.f / 255.f, 1.f / 255.f, 1.f / 255.f};
    static const float kDenorm[3] = {255.f, 255.f, 255.f};

    // Scratch buffer for one upscaled tile as tightly packed RGB8.
    const int maxTileIn = tileSize + 2 * overlap;
    std::vector<unsigned char> tileRgb((size_t)maxTileIn * M * maxTileIn * M * 3);

    for (int yi = 0; yi < yTiles; yi++) {
        for (int xi = 0; xi < xTiles; xi++) {
            if (cancelFlag.load()) return kErrCancelled;

            const int x0 = xi * tileSize;
            const int y0 = yi * tileSize;
            const int x1 = std::min(x0 + tileSize, w);
            const int y1 = std::min(y0 + tileSize, h);

            // Padded read window, clipped to the image.
            const int px0 = std::max(x0 - overlap, 0);
            const int py0 = std::max(y0 - overlap, 0);
            const int px1 = std::min(x1 + overlap, w);
            const int py1 = std::min(y1 + overlap, h);

            ncnn::Mat tile = ncnn::Mat::from_pixels_roi(in, inType, w, h, inStride,
                                                        px0, py0, px1 - px0, py1 - py0);
            if (tile.empty()) return kErrExtract;

            // Replicate edges where the padding ran off the image so every
            // tile the network sees has the same context on all four sides.
            const int padL = overlap - (x0 - px0);
            const int padT = overlap - (y0 - py0);
            const int padR = overlap - (px1 - x1);
            const int padB = overlap - (py1 - y1);
            if (padL || padT || padR || padB) {
                ncnn::Mat padded;
                ncnn::copy_make_border(tile, padded, padT, padB, padL, padR, ncnn::BORDER_REPLICATE, 0.f);
                tile = padded;
            }
            tile.substract_mean_normalize(0, kNorm);

            ncnn::Mat outTile;
            {
                ncnn::Extractor ex = net_.create_extractor();
                ex.input(inputName_.c_str(), tile);
                if (ex.extract(outputName_.c_str(), outTile) != 0 || outTile.empty()) return kErrExtract;
            }
            // Expected geometry: (tileW+2*overlap)*M x (tileH+2*overlap)*M x 3.
            if (outTile.c != 3 || outTile.w != tile.w * M || outTile.h != tile.h * M) return kErrExtract;

            outTile.substract_mean_normalize(0, kDenorm);
            outTile.to_pixels(tileRgb.data(), ncnn::Mat::PIXEL_RGB);

            // Copy the un-padded centre into the destination.
            const int srcRow = outTile.w * 3;
            const int innerW = (x1 - x0) * M;
            const int innerH = (y1 - y0) * M;
            const int srcX = overlap * M;
            const int srcY = overlap * M;
            const int dstX0 = x0 * scale;
            const int dstY0 = y0 * scale;

            if (down == 1) {
                for (int y = 0; y < innerH; y++) {
                    const unsigned char* s = tileRgb.data() + (size_t)(srcY + y) * srcRow + srcX * 3;
                    unsigned char* d = out + (size_t)(dstY0 + y) * outStride + (size_t)dstX0 * outChannels;
                    if (outChannels == 3) {
                        std::memcpy(d, s, (size_t)innerW * 3);
                    } else {
                        for (int x = 0; x < innerW; x++) {
                            d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 255;
                            d += 4; s += 3;
                        }
                    }
                }
            } else {
                // 2x2 box filter: the 4x network output averaged down to 2x.
                const int outW = innerW / 2;
                const int outH = innerH / 2;
                for (int y = 0; y < outH; y++) {
                    const unsigned char* s0 = tileRgb.data() + (size_t)(srcY + y * 2) * srcRow + srcX * 3;
                    const unsigned char* s1 = s0 + srcRow;
                    unsigned char* d = out + (size_t)(dstY0 + y) * outStride + (size_t)dstX0 * outChannels;
                    for (int x = 0; x < outW; x++) {
                        for (int c = 0; c < 3; c++) {
                            const int sum = s0[c] + s0[3 + c] + s1[c] + s1[3 + c];
                            d[c] = (unsigned char)((sum + 2) >> 2);
                        }
                        if (outChannels == 4) d[3] = 255;
                        d += outChannels;
                        s0 += 6;
                        s1 += 6;
                    }
                }
            }

            done++;
            if (progress) progress(user, done, total);
        }
    }
    return kOk;
}

const char* Engine::errorString(int code) {
    switch (code) {
        case kOk: return "ok";
        case kErrParam: return "param_load_failed";
        case kErrBin: return "bin_load_failed";
        case kErrNoBlobs: return "no_blob_names";
        case kErrNotLoaded: return "engine_not_loaded";
        case kErrBadArgs: return "bad_arguments";
        case kErrExtract: return "inference_failed";
        case kErrCancelled: return "cancelled";
        default: return "unknown";
    }
}

}  // namespace photolift
