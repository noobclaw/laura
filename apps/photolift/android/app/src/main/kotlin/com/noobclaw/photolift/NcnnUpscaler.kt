package com.noobclaw.photolift

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.util.Log

/**
 * Thin Kotlin face of libphotolift.so (native/photolift_core.cpp via
 * photolift_jni.cpp). One instance == one loaded Real-ESRGAN network.
 *
 * [available] is false when the shared library could not be loaded at all
 * (a build without the native step, or an ABI the package does not carry);
 * the Dart side then falls back to its pure-Dart resampler and labels the
 * result accordingly. Nothing here throws across the JNI boundary.
 */
class NcnnUpscaler private constructor(private var handle: Long) {

    /** Receives per-tile progress on the worker thread. */
    fun interface Progress {
        fun onProgress(done: Int, total: Int)
    }

    val gpuActive: Boolean
        get() = handle != 0L && nativeGpuActive(handle)

    /** Returns a photolift ErrorCode (0 ok, -100 cancelled). */
    fun process(
        input: Bitmap,
        output: Bitmap,
        scale: Int,
        tileSize: Int,
        overlap: Int,
        progress: Progress?,
    ): Int {
        if (handle == 0L) return ERR_NOT_LOADED
        return nativeProcess(handle, input, output, scale, tileSize, overlap, progress)
    }

    fun cancel() {
        if (handle != 0L) nativeCancel(handle)
    }

    fun close() {
        if (handle != 0L) {
            nativeDestroy(handle)
            handle = 0L
        }
    }

    companion object {
        private const val TAG = "PhotoLift"

        const val ERR_OK = 0
        const val ERR_NOT_LOADED = -4
        const val ERR_CANCELLED = -100

        val available: Boolean = try {
            System.loadLibrary("photolift")
            true
        } catch (t: Throwable) {
            Log.w(TAG, "native upscaler unavailable: $t")
            false
        }

        /** Null when the library is missing or the model failed to load. */
        fun create(
            assets: AssetManager,
            paramAsset: String,
            binAsset: String,
            useGpu: Boolean,
            modelScale: Int,
        ): NcnnUpscaler? {
            if (!available) return null
            val h = try {
                nativeCreate(assets, paramAsset, binAsset, useGpu, modelScale)
            } catch (t: Throwable) {
                Log.e(TAG, "nativeCreate threw: $t")
                0L
            }
            return if (h == 0L) null else NcnnUpscaler(h)
        }

        fun tileCount(w: Int, h: Int, tile: Int): Int =
            if (available) nativeTileCount(w, h, tile) else 0

        @JvmStatic private external fun nativeCreate(
            assets: AssetManager, paramAsset: String, binAsset: String, useGpu: Boolean, modelScale: Int,
        ): Long
        @JvmStatic private external fun nativeDestroy(handle: Long)
        @JvmStatic private external fun nativeGpuActive(handle: Long): Boolean
        @JvmStatic private external fun nativeCancel(handle: Long)
        @JvmStatic private external fun nativeTileCount(w: Int, h: Int, tile: Int): Int
        @JvmStatic private external fun nativeProcess(
            handle: Long, input: Bitmap, output: Bitmap, scale: Int, tileSize: Int, overlap: Int,
            callback: Progress?,
        ): Int
    }
}
