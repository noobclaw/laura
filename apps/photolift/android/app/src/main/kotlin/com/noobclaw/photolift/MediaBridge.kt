package com.noobclaw.photolift

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Media bridge — the Android half of the `photolift/media` channel.
 * Counterpart: ios/Runner/MediaBridge.swift.
 *
 *  - `pick` -> {path, width, height} | null (user backed out)
 *       The chosen image is copied into the app cache (the picker's URI is
 *       transient), so no storage permission is ever requested: the system
 *       photo picker (Android 13+) or the documents UI (older) hands us a
 *       one-off grant. Dimensions honour EXIF rotation.
 *       errors: picker_unavailable | copy_failed
 *  - `saveToGallery` {path, displayName} -> true
 *       Inserts into MediaStore under Pictures/PhotoLift. Scoped storage
 *       (API 29+) needs no permission for the app's own inserts.
 *       errors: save_failed
 */
class MediaBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private companion object {
        const val TAG = "PhotoLift"
        const val CHANNEL = "photolift/media"
        const val REQUEST_PICK = 0x9F01
    }

    private val channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    private var pending: MethodChannel.Result? = null

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "saveToGallery" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("displayName") ?: "PhotoLift_${System.currentTimeMillis()}.jpg"
                if (path == null) {
                    result.error("save_failed", "path required", null)
                } else {
                    try {
                        saveToGallery(File(path), name)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "saveToGallery failed", e)
                        result.error("save_failed", e.toString(), null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("picker_unavailable", "picker already open", null)
            return
        }
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }
        pending = result
        try {
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            // No picker at all (rare) — try the generic chooser once.
            try {
                val fallback = Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*" }
                activity.startActivityForResult(Intent.createChooser(fallback, null), REQUEST_PICK)
            } catch (e2: Exception) {
                pending = null
                result.error("picker_unavailable", e2.toString(), null)
            }
        }
    }

    /** Called from MainActivity.onActivityResult; true when consumed. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            result.success(copyIntoCache(uri))
        } catch (e: Exception) {
            Log.e(TAG, "copy picked image failed", e)
            result.error("copy_failed", e.toString(), null)
        }
        return true
    }

    private fun copyIntoCache(uri: Uri): Map<String, Any> {
        val resolver = activity.contentResolver
        val mime = resolver.getType(uri) ?: "image/jpeg"
        val ext = when {
            mime.contains("png") -> "png"
            mime.contains("webp") -> "webp"
            mime.contains("heic") || mime.contains("heif") -> "heic"
            else -> "jpg"
        }
        val dir = File(activity.cacheDir, "picked").apply { mkdirs() }
        // Only the newest pick is kept; older copies would pile up otherwise.
        dir.listFiles()?.forEach { it.delete() }
        val dest = File(dir, "picked_${System.currentTimeMillis()}.$ext")
        resolver.openInputStream(uri).use { input ->
            if (input == null) throw IllegalStateException("cannot open $uri")
            FileOutputStream(dest).use { out -> input.copyTo(out) }
        }
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(dest.path, opts)
        var w = opts.outWidth
        var h = opts.outHeight
        if (w <= 0 || h <= 0) {
            dest.delete()
            throw IllegalStateException("not an image")
        }
        try {
            val o = ExifInterface(dest.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            if (o == ExifInterface.ORIENTATION_ROTATE_90 || o == ExifInterface.ORIENTATION_ROTATE_270 ||
                o == ExifInterface.ORIENTATION_TRANSPOSE || o == ExifInterface.ORIENTATION_TRANSVERSE) {
                val t = w; w = h; h = t
            }
        } catch (_: Exception) {
            // PNG/WebP have no EXIF; bounds already correct.
        }
        return mapOf("path" to dest.path, "width" to w, "height" to h)
    }

    private fun saveToGallery(file: File, displayName: String) {
        if (!file.exists()) throw IllegalStateException("file missing")
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/PhotoLift")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: throw IllegalStateException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IllegalStateException("cannot open output")
                file.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
