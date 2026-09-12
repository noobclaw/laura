// See photolift_core.h for the contract. Kept C++11 and exception-free.
// The arithmetic (padding, stitching, quantisation, alpha) is in
// photolift_tiling.h; this file is the ncnn adapter around it.
#include "photolift_core.h"

#include <algorithm>
#include <cstring>

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
    return tiling::tileCount(w, h, tileSize);
}

Engine::Engine()
    : cancelFlag(false), loaded_(false), gpu_(false), modelScale_(4), heapBudgetMb_(0) {}

Engine::~Engine() {
    // ncnn::Net releases its pipelines in its own destructor; the Vulkan
    // instance stays alive for the next engine.
}

void Engine::configureOptions(bool preferGpu) {
    ncnn::Option& opt = net_.opt;
    opt.num_threads = std::max(1, ncnn::get_big_cpu_count());
    // Same numeric profile Real-ESRGAN-ncnn-vulkan ships with: fp16 storage
    // and packing for speed, fp32 arithmetic to keep colours faithful. The
    // reference also sets use_int8_storage for its uint8 upload shader; we
    // feed float Mats, so it is left off.
    opt.use_fp16_packed = true;
    opt.use_fp16_storage = true;
    opt.use_fp16_arithmetic = false;
    opt.use_int8_storage = false;
    opt.use_int8_arithmetic = false;
    opt.use_packing_layout = true;
    gpu_ = false;
    heapBudgetMb_ = 0;
#if NCNN_VULKAN
    if (preferGpu && ensureVulkan()) {
        opt.use_vulkan_compute = true;
        const int gpuIndex = ncnn::get_default_gpu_index();
        net_.set_vulkan_device(gpuIndex);
        const ncnn::VulkanDevice* dev = ncnn::get_gpu_device(gpuIndex);
        heapBudgetMb_ = dev ? (int)dev->get_heap_budget() : 0;
        gpu_ = true;
    } else {
        opt.use_vulkan_compute = false;
    }
#else
    (void)preferGpu;
#endif
}

int Engine::effectiveTileSize(int requested) const {
    int t = clampi(requested, 32, 1024);
    if (gpu_ && heapBudgetMb_ > 0) {
        // Real-ESRGAN-ncnn-vulkan main.cpp: >1900 MB -> 200, >550 -> 100,
        // >190 -> 64, else 32 for the RRDB x4plus model. The compact model
        // needs ~1/15 of that activation memory, so the caps are looser.
        if (heapBudgetMb_ <= 190) t = std::min(t, 64);
        else if (heapBudgetMb_ <= 550) t = std::min(t, 128);
    }
    return t;
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

// tiling::InferFn adapter: CHW float in -> ncnn::Mat -> network -> CHW float out.
int Engine::inferTile(void* user, const float* in, int w, int h, float* out) {
    Engine* self = static_cast<Engine*>(user);
    const int M = self->modelScale_;
    const size_t plane = (size_t)w * h;

    ncnn::Mat tile(w, h, 3);
    if (tile.empty()) return 1;
    for (int c = 0; c < 3; c++) {
        std::memcpy(tile.channel(c).data, in + (size_t)c * plane, plane * sizeof(float));
    }

    ncnn::Mat outTile;
    {
        ncnn::Extractor ex = self->net_.create_extractor();
        ex.input(self->inputName_.c_str(), tile);
        if (ex.extract(self->outputName_.c_str(), outTile) != 0 || outTile.empty()) return 1;
    }
    // Expected geometry: (w*M) x (h*M) x 3, fp32 (Extractor converts fp16
    // storage back to fp32 on extract).
    if (outTile.c != 3 || outTile.w != w * M || outTile.h != h * M || outTile.elemsize != 4u) return 1;

    const size_t outPlane = (size_t)outTile.w * outTile.h;
    for (int c = 0; c < 3; c++) {
        std::memcpy(out + (size_t)c * outPlane, outTile.channel(c).data, outPlane * sizeof(float));
    }
    return 0;
}

int Engine::process(const unsigned char* in, int w, int h, int inChannels, int inStride,
                    unsigned char* out, int outChannels, int outStride,
                    int scale, int tileSize, int overlap,
                    ProgressFn progress, void* user) {
    if (!loaded_) return kErrNotLoaded;
    if (!in || !out || w <= 0 || h <= 0) return kErrBadArgs;
    if ((inChannels != 3 && inChannels != 4) || (outChannels != 3 && outChannels != 4)) return kErrBadArgs;
    if (scale != 2 && scale != 4) return kErrBadArgs;
    if (modelScale_ != 4) return kErrBadArgs;
    tileSize = effectiveTileSize(tileSize);
    overlap = clampi(overlap, 0, 64);

    const int rc = tiling::processTiled(in, w, h, inChannels, inStride,
                                        out, outChannels, outStride,
                                        modelScale_, scale, tileSize, overlap,
                                        &Engine::inferTile, this,
                                        &cancelFlag, progress, user);
    switch (rc) {
        case tiling::kDone: return kOk;
        case tiling::kCancelled: return kErrCancelled;
        case tiling::kBadArgs: return kErrBadArgs;
        default: return kErrExtract;
    }
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
