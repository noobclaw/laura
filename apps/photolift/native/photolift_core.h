// PhotoLift — on-device super-resolution core shared by the Android (JNI) and
// iOS (Objective-C++) bridges. Wraps one Real-ESRGAN "general-x4v3" network
// (SRVGGNetCompact, BSD-3 weights converted to ncnn) and runs it tile by tile
// so a phone never has to hold a full-resolution feature map in memory.
//
// Contract:
//  - Input pixels are 8-bit RGB or RGBA (inChannels 3 or 4) with a row stride;
//    output pixels are written as RGB or RGBA (alpha forced to 255).
//  - The model is a fixed 4x network. scale == 4 writes it straight out;
//    scale == 2 box-filters every 4x tile down by two before writing, so the
//    output buffer is only (w*2)*(h*2) and never the 4x size.
//  - Progress is reported per tile; cancellation is checked before every tile
//    (the caller flips [Engine::cancelFlag]) and returns kErrCancelled.
//  - No exceptions, no RTTI: ncnn's prebuilt libraries propagate
//    -fno-exceptions/-fno-rtti to consumers.
#pragma once

#include <atomic>
#include <string>

#include "net.h"

#if defined(__ANDROID__)
#include <android/asset_manager.h>
#endif

namespace photolift {

enum ErrorCode {
    kOk = 0,
    kErrParam = -1,        // .param failed to load
    kErrBin = -2,          // .bin failed to load
    kErrNoBlobs = -3,      // network has no input/output blob names
    kErrNotLoaded = -4,
    kErrBadArgs = -5,
    kErrExtract = -10,     // ncnn inference failed on a tile
    kErrCancelled = -100,
};

/// Per-tile progress callback: `done` tiles finished out of `total`.
typedef void (*ProgressFn)(void* user, int done, int total);

class Engine {
public:
    Engine();
    ~Engine();

    /// Load .param/.bin from file paths (iOS bundle, or Android files dir).
    int loadFromFiles(const char* paramPath, const char* binPath, bool preferGpu, int modelScale);

#if defined(__ANDROID__)
    /// Load straight out of the APK's asset manager (Flutter asset keys).
    int loadFromAssets(AAssetManager* mgr, const char* paramAsset, const char* binAsset,
                       bool preferGpu, int modelScale);
#endif

    bool loaded() const { return loaded_; }
    /// True when Vulkan compute is actually in use for this network.
    bool gpuActive() const { return gpu_; }
    int modelScale() const { return modelScale_; }

    /// Upscale [in] (w x h, inChannels 3/4, inStride bytes per row) into [out]
    /// ((w*scale) x (h*scale), outChannels 3/4, outStride bytes per row).
    /// scale must be 2 or 4. tileSize is the un-padded tile edge in input
    /// pixels (200-400 recommended); overlap is the replicated padding.
    int process(const unsigned char* in, int w, int h, int inChannels, int inStride,
                unsigned char* out, int outChannels, int outStride,
                int scale, int tileSize, int overlap,
                ProgressFn progress, void* user);

    /// Set to true from any thread to abort the running [process].
    std::atomic<bool> cancelFlag;

    static const char* errorString(int code);

private:
    int finishLoad(bool preferGpu, int modelScale);
    void configureOptions(bool preferGpu);

    bool loaded_;
    bool gpu_;
    int modelScale_;
    std::string inputName_;
    std::string outputName_;
    ncnn::Net net_;
};

/// Number of tiles [process] will run for the given geometry — used by the
/// bridges to size the progress bar before the first tile finishes.
int tileCount(int w, int h, int tileSize);

}  // namespace photolift
