package com.noobclaw.photolift

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Upscale bridge — the Android half of the `photolift/upscale` channel.
 * Counterpart: ios/Runner/UpscaleBridge.swift (same contract, see
 * lib/tool/native_upscaler.dart for the Dart side).
 *
 * Methods:
 *  - `capabilities` -> {native: Bool}
 *  - `upscale` {jobId, inputPath, outputPath, scale(2|4), model, useGpu, tag,
 *               tagText, maxOutPixels, maxOutLongEdge}
 *       -> {outputPath, outWidth, outHeight, inWidth, inHeight, downscaled,
 *           engine: "ncnn-gpu"|"ncnn-cpu", elapsedMs}
 *       errors: busy | engine_unavailable | engine_load_failed | decode_failed |
 *               too_large | inference_failed | write_failed | cancelled
 *  - `cancel` -> null
 * Events on `photolift/upscale/progress`: {jobId, done, total, stage}
 *
 * One job at a time on a dedicated thread; every callback to Flutter is
 * posted to the main looper.
 */
class UpscaleBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private companion object {
        const val TAG = "PhotoLift"
        const val METHOD_CHANNEL = "photolift/upscale"
        const val EVENT_CHANNEL = "photolift/upscale/progress"

        /** Un-padded tile edge in input pixels; overlap is replicated context. */
        const val TILE_GPU = 256
        const val TILE_CPU = 192
        const val OVERLAP = 12
        const val MODEL_SCALE = 4
        const val JPEG_QUALITY = 94
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
        it.setStreamHandler(this)
    }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var events: EventChannel.EventSink? = null

    private val busy = AtomicBoolean(false)
    @Volatile private var cancelRequested = false
    @Volatile private var engine: NcnnUpscaler? = null
    private var engineKey: String? = null

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(mapOf("native" to NcnnUpscaler.available))
            "cancel" -> {
                cancelRequested = true
                engine?.cancel()
                result.success(null)
            }
            "upscale" -> startJob(call, result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        cancelRequested = true
        engine?.cancel()
        worker.shutdown()
        engine?.close()
        engine = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun emit(jobId: String, done: Int, total: Int, stage: String) {
        main.post {
            events?.success(mapOf("jobId" to jobId, "done" to done, "total" to total, "stage" to stage))
        }
    }

    private fun startJob(call: MethodCall, result: MethodChannel.Result) {
        if (!NcnnUpscaler.available) {
            result.error("engine_unavailable", "native library not loaded", null)
            return
        }
        if (!busy.compareAndSet(false, true)) {
            result.error("busy", "another upscale is running", null)
            return
        }
        val jobId = call.argument<String>("jobId") ?: "job"
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val scale = call.argument<Int>("scale") ?: 2
        val model = call.argument<String>("model") ?: "general-x4v3-dn0"
        val useGpu = call.argument<Boolean>("useGpu") ?: true
        val tag = call.argument<Boolean>("tag") ?: false
        val tagText = call.argument<String>("tagText") ?: "PhotoLift"
        val maxOutPixels = (call.argument<Number>("maxOutPixels") ?: 24_000_000).toLong()
        val maxOutLongEdge = call.argument<Int>("maxOutLongEdge") ?: 8192
        if (inputPath == null || outputPath == null || (scale != 2 && scale != 4)) {
            busy.set(false)
            result.error("bad_args", "inputPath/outputPath/scale required", null)
            return
        }
        cancelRequested = false
        worker.execute {
            val outcome = runCatching {
                runJob(jobId, inputPath, outputPath, scale, model, useGpu, tag, tagText, maxOutPixels, maxOutLongEdge)
            }
            busy.set(false)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { e ->
                        if (e is JobError) result.error(e.code, e.message, null)
                        else {
                            Log.e(TAG, "upscale crashed", e)
                            result.error("inference_failed", e.toString(), null)
                        }
                    },
                )
            }
        }
    }

    private class JobError(val code: String, message: String) : RuntimeException(message)

    private fun ensureEngine(model: String, useGpu: Boolean): NcnnUpscaler {
        val key = "$model/${if (useGpu) "gpu" else "cpu"}"
        engine?.let { if (engineKey == key) return it }
        engine?.close()
        engine = null
        val loader = FlutterInjector.instance().flutterLoader()
        val param = loader.getLookupKeyForAsset("assets/models/$model.param")
        val bin = loader.getLookupKeyForAsset("assets/models/$model.bin")
        // A Vulkan device that exists but fails to build the pipelines (odd
        // drivers) must not take the whole feature down: fall back to CPU.
        val e = NcnnUpscaler.create(context.assets, param, bin, useGpu, MODEL_SCALE)
            ?: (if (useGpu) {
                Log.w(TAG, "GPU engine failed for $model, retrying on CPU")
                NcnnUpscaler.create(context.assets, param, bin, false, MODEL_SCALE)
            } else null)
            ?: throw JobError("engine_load_failed", "could not load $model")
        engine = e
        engineKey = key
        return e
    }

    /**
     * Fit the input so the output stays inside the pixel / long-edge caps —
     * a phone cannot hold a 16000x12000 RGBA bitmap. Returns the input size to
     * decode to (possibly smaller than the file).
     */
    private fun fitInput(w: Int, h: Int, scale: Int, maxOutPixels: Long, maxOutLongEdge: Int): Pair<Int, Int> {
        val maxInLong = maxOutLongEdge / scale
        val maxInPixels = maxOutPixels / (scale.toLong() * scale)
        var f = 1.0
        val longEdge = max(w, h)
        if (longEdge > maxInLong) f = min(f, maxInLong.toDouble() / longEdge)
        val px = w.toLong() * h
        if (px > maxInPixels) f = min(f, sqrt(maxInPixels.toDouble() / px))
        if (f >= 1.0) return w to h
        return max(1, (w * f).toInt()) to max(1, (h * f).toInt())
    }

    private fun runJob(
        jobId: String, inputPath: String, outputPath: String, scale: Int, model: String,
        useGpu: Boolean, tag: Boolean, tagText: String, maxOutPixels: Long, maxOutLongEdge: Int,
    ): Map<String, Any?> {
        val t0 = SystemClock.elapsedRealtime()
        emit(jobId, 0, 1, "decode")
        val src = File(inputPath)
        if (!src.exists()) throw JobError("decode_failed", "input missing")

        // ImageDecoder applies EXIF orientation and lets us decode straight to
        // a smaller size instead of decoding full-size and shrinking.
        var origW = 0
        var origH = 0
        var targetW = 0
        var targetH = 0
        val input: Bitmap = try {
            val source = ImageDecoder.createSource(src)
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.isMutableRequired = false
                origW = info.size.width
                origH = info.size.height
                val (tw, th) = fitInput(origW, origH, scale, maxOutPixels, maxOutLongEdge)
                targetW = tw
                targetH = th
                if (tw != origW || th != origH) decoder.setTargetSize(tw, th)
            }
        } catch (e: OutOfMemoryError) {
            throw JobError("too_large", "not enough memory to decode the photo")
        } catch (e: Exception) {
            throw JobError("decode_failed", e.toString())
        }
        val downscaled = input.width != origW || input.height != origH
        if (cancelRequested) {
            input.recycle()
            throw JobError("cancelled", "cancelled")
        }

        // ImageDecoder may hand back a HARDWARE/other config despite the
        // allocator hint on some OEM builds; the JNI side needs ARGB_8888.
        val inRgba = if (input.config == Bitmap.Config.ARGB_8888) input else {
            val c = input.copy(Bitmap.Config.ARGB_8888, false)
            input.recycle()
            c ?: throw JobError("decode_failed", "bitmap copy failed")
        }

        val engine = ensureEngine(model, useGpu)
        val tile = if (engine.gpuActive) TILE_GPU else TILE_CPU
        val total = max(1, NcnnUpscaler.tileCount(inRgba.width, inRgba.height, tile))
        emit(jobId, 0, total, "infer")

        val output: Bitmap = try {
            Bitmap.createBitmap(inRgba.width * scale, inRgba.height * scale, Bitmap.Config.ARGB_8888)
        } catch (e: OutOfMemoryError) {
            inRgba.recycle()
            throw JobError("too_large", "not enough memory for ${inRgba.width * scale}x${inRgba.height * scale}")
        }

        val rc = engine.process(inRgba, output, scale, tile, OVERLAP) { done, t ->
            emit(jobId, done, t, "infer")
        }
        inRgba.recycle()
        if (rc == NcnnUpscaler.ERR_CANCELLED || cancelRequested) {
            output.recycle()
            throw JobError("cancelled", "cancelled")
        }
        if (rc != NcnnUpscaler.ERR_OK) {
            output.recycle()
            throw JobError("inference_failed", "native error $rc")
        }

        if (tag) drawTag(output, tagText)

        emit(jobId, total, total, "encode")
        try {
            val out = File(outputPath)
            out.parentFile?.mkdirs()
            val tmp = File(out.path + ".tmp")
            FileOutputStream(tmp).use { fos ->
                if (!output.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, fos)) {
                    throw JobError("write_failed", "JPEG encode failed")
                }
                fos.fd.sync()
            }
            if (!tmp.renameTo(out)) throw JobError("write_failed", "rename failed")
        } catch (e: JobError) {
            output.recycle()
            throw e
        } catch (e: Exception) {
            output.recycle()
            throw JobError("write_failed", e.toString())
        }
        val outW = output.width
        val outH = output.height
        output.recycle()
        return mapOf(
            "outputPath" to outputPath,
            "outWidth" to outW,
            "outHeight" to outH,
            "inWidth" to targetW,
            "inHeight" to targetH,
            "downscaled" to downscaled,
            "engine" to if (engine.gpuActive) "ncnn-gpu" else "ncnn-cpu",
            "elapsedMs" to (SystemClock.elapsedRealtime() - t0),
        )
    }

    /** Free-tier corner tag: a small translucent pill with the app name. */
    private fun drawTag(bitmap: Bitmap, text: String) {
        val canvas = Canvas(bitmap)
        val textSize = max(18f, bitmap.width * 0.022f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            this.textSize = textSize
            isFakeBoldText = true
        }
        val padX = textSize * 0.7f
        val padY = textSize * 0.45f
        val margin = bitmap.width * 0.02f
        val textW = paint.measureText(text)
        val fm = paint.fontMetrics
        val textH = fm.descent - fm.ascent
        val right = bitmap.width - margin
        val bottom = bitmap.height - margin
        val rect = RectF(right - textW - padX * 2, bottom - textH - padY * 2, right, bottom)
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(140, 0, 0, 0) }
        canvas.drawRoundRect(rect, textSize * 0.6f, textSize * 0.6f, bg)
        canvas.drawText(text, rect.left + padX, rect.bottom - padY - fm.descent, paint)
    }
}
