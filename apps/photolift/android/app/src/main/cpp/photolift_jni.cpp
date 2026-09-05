// JNI glue between com.noobclaw.photolift.NcnnUpscaler and photolift::Engine.
// Pixels travel as Android Bitmaps (ARGB_8888 = RGBA bytes in memory) locked
// in place, so neither the input nor the 4x output is ever copied in Java.
#include <jni.h>

#include <android/asset_manager_jni.h>
#include <android/bitmap.h>
#include <android/log.h>

#include "photolift_core.h"

#define LOG_TAG "PhotoLiftNative"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

struct ProgressCtx {
    JNIEnv* env;
    jobject callback;
    jmethodID method;
};

void onProgress(void* user, int done, int total) {
    ProgressCtx* ctx = static_cast<ProgressCtx*>(user);
    if (ctx && ctx->callback && ctx->method) {
        ctx->env->CallVoidMethod(ctx->callback, ctx->method, (jint)done, (jint)total);
        if (ctx->env->ExceptionCheck()) ctx->env->ExceptionClear();
    }
}

photolift::Engine* toEngine(jlong h) { return reinterpret_cast<photolift::Engine*>(h); }

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeCreate(JNIEnv* env, jclass, jobject assetManager,
                                                       jstring paramAsset, jstring binAsset,
                                                       jboolean useGpu, jint modelScale) {
    AAssetManager* mgr = AAssetManager_fromJava(env, assetManager);
    if (!mgr) {
        LOGE("AAssetManager_fromJava failed");
        return 0;
    }
    const char* p = env->GetStringUTFChars(paramAsset, nullptr);
    const char* b = env->GetStringUTFChars(binAsset, nullptr);
    photolift::Engine* engine = new photolift::Engine();
    const int rc = engine->loadFromAssets(mgr, p, b, useGpu == JNI_TRUE, (int)modelScale);
    env->ReleaseStringUTFChars(paramAsset, p);
    env->ReleaseStringUTFChars(binAsset, b);
    if (rc != photolift::kOk) {
        LOGE("engine load failed: %s", photolift::Engine::errorString(rc));
        delete engine;
        return 0;
    }
    LOGI("engine loaded, gpu=%d", engine->gpuActive() ? 1 : 0);
    return reinterpret_cast<jlong>(engine);
}

JNIEXPORT void JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeDestroy(JNIEnv*, jclass, jlong handle) {
    delete toEngine(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeGpuActive(JNIEnv*, jclass, jlong handle) {
    photolift::Engine* e = toEngine(handle);
    return (e && e->gpuActive()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeCancel(JNIEnv*, jclass, jlong handle) {
    photolift::Engine* e = toEngine(handle);
    if (e) e->cancelFlag.store(true);
}

JNIEXPORT jint JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeTileCount(JNIEnv*, jclass, jint w, jint h, jint tile) {
    return (jint)photolift::tileCount((int)w, (int)h, (int)tile);
}

/// Runs the network over `inBitmap` into `outBitmap` (both ARGB_8888; the
/// output must be exactly scale× the input). Returns a photolift::ErrorCode.
JNIEXPORT jint JNICALL
Java_com_noobclaw_photolift_NcnnUpscaler_nativeProcess(JNIEnv* env, jclass, jlong handle,
                                                        jobject inBitmap, jobject outBitmap,
                                                        jint scale, jint tileSize, jint overlap,
                                                        jobject callback) {
    photolift::Engine* e = toEngine(handle);
    if (!e) return photolift::kErrNotLoaded;
    e->cancelFlag.store(false);

    AndroidBitmapInfo inInfo, outInfo;
    if (AndroidBitmap_getInfo(env, inBitmap, &inInfo) < 0 ||
        AndroidBitmap_getInfo(env, outBitmap, &outInfo) < 0) {
        LOGE("AndroidBitmap_getInfo failed");
        return photolift::kErrBadArgs;
    }
    if (inInfo.format != ANDROID_BITMAP_FORMAT_RGBA_8888 ||
        outInfo.format != ANDROID_BITMAP_FORMAT_RGBA_8888) {
        LOGE("bitmaps must be ARGB_8888");
        return photolift::kErrBadArgs;
    }
    if (outInfo.width != inInfo.width * (uint32_t)scale || outInfo.height != inInfo.height * (uint32_t)scale) {
        LOGE("output bitmap is not scale x input");
        return photolift::kErrBadArgs;
    }

    void* inPixels = nullptr;
    void* outPixels = nullptr;
    if (AndroidBitmap_lockPixels(env, inBitmap, &inPixels) < 0) return photolift::kErrBadArgs;
    if (AndroidBitmap_lockPixels(env, outBitmap, &outPixels) < 0) {
        AndroidBitmap_unlockPixels(env, inBitmap);
        return photolift::kErrBadArgs;
    }

    jmethodID method = nullptr;
    if (callback) {
        jclass cls = env->GetObjectClass(callback);
        method = env->GetMethodID(cls, "onProgress", "(II)V");
        env->DeleteLocalRef(cls);
    }
    ProgressCtx ctx{env, callback, method};

    const int rc = e->process(static_cast<const unsigned char*>(inPixels),
                              (int)inInfo.width, (int)inInfo.height, 4, (int)inInfo.stride,
                              static_cast<unsigned char*>(outPixels), 4, (int)outInfo.stride,
                              (int)scale, (int)tileSize, (int)overlap, onProgress, &ctx);

    AndroidBitmap_unlockPixels(env, outBitmap);
    AndroidBitmap_unlockPixels(env, inBitmap);
    if (rc != photolift::kOk && rc != photolift::kErrCancelled) {
        LOGE("process failed: %s", photolift::Engine::errorString(rc));
    }
    return rc;
}

}  // extern "C"
