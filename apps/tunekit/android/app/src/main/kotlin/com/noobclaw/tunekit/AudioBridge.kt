package com.noobclaw.tunekit

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin

/**
 * Microphone capture + sample-accurate metronome for TuneBench.
 *
 * Contract with the Dart side: lib/tool/audio_bridge.dart (single source of
 * truth for method names and event shapes). The Swift twin is
 * ios/Runner/AudioBridge.swift.
 *
 * Metronome design: the click schedule lives INSIDE the audio render loop.
 * A dedicated thread streams float PCM into an AudioTrack; every output
 * frame has an absolute index, and a tick is due when that index reaches
 * `nextTick` (a double, advanced by the exact interval in samples, so no
 * drift accumulates). Timing therefore comes from the audio clock, never
 * from Handler/Timer wake-ups, and keeps running with the screen off for as
 * long as the process lives.
 */
/** One sounding click: when it started (in output frames) and which accent level. */
private class Voice(val start: Long, val kind: Int)

class AudioBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "TuneBenchAudio"
        const val PERMISSION_REQUEST = 7101
        private const val PREFS = "tunekit_audio"
        private const val KEY_ASKED = "mic_asked"
        private const val MIC_RATE = 44100
        private const val MIC_CHUNK = 2048
    }

    private val main = Handler(Looper.getMainLooper())
    private val method = MethodChannel(messenger, "tunekit/audio")
    private val micChannel = EventChannel(messenger, "tunekit/audio/mic")
    private val eventChannel = EventChannel(messenger, "tunekit/audio/events")

    @Volatile private var micSink: EventChannel.EventSink? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null

    private var pendingPermission: MethodChannel.Result? = null

    // ---- microphone ----
    private var record: AudioRecord? = null
    private var micThread: Thread? = null
    @Volatile private var micRunning = false

    // ---- metronome ----
    private val metro = Metronome()

    init {
        method.setMethodCallHandler(this)
        micChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { micSink = events }
            override fun onCancel(arguments: Any?) { micSink = null }
        })
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
    }

    fun dispose() {
        stopMic()
        metro.stop(notify = false)
        method.setMethodCallHandler(null)
        micChannel.setStreamHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ---------------------------------------------------------------- methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "micStatus" -> result.success(micStatus())
            "micRequest" -> requestMic(result)
            "openSettings" -> { openSettings(); result.success(null) }
            "micStart" -> startMic(result)
            "micStop" -> { stopMic(); result.success(null) }
            "metroStart" -> {
                metro.configure(call)
                if (metro.start()) result.success(null)
                else result.error("audio_unavailable", "Could not open the audio output", null)
            }
            "metroUpdate" -> { metro.configure(call); result.success(null) }
            "metroStop" -> { metro.stop(notify = false); result.success(null) }
            "metroIsPlaying" -> result.success(metro.isPlaying)
            else -> result.notImplemented()
        }
    }

    private fun emit(map: Map<String, Any?>) {
        main.post { eventSink?.success(map) }
    }

    // ------------------------------------------------------------ permission

    private fun granted(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun micStatus(): String {
        if (granted()) return "granted"
        val asked = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ASKED, false)
        if (!asked) return "undetermined"
        // After a refusal, Android only shows the rationale flag while the
        // system will still prompt; once it stops prompting we must send the
        // user to Settings ourselves.
        return if (activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO))
            "denied" else "permanentlyDenied"
    }

    private fun requestMic(result: MethodChannel.Result) {
        if (granted()) { result.success("granted"); return }
        if (pendingPermission != null) { result.success(micStatus()); return }
        pendingPermission = result
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ASKED, true).apply()
        // minSdk 24: the framework APIs are available, no androidx.core needed.
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val r = pendingPermission ?: return true
        pendingPermission = null
        r.success(micStatus())
        return true
    }

    private fun openSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + activity.packageName))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "openSettings failed", e)
        }
    }

    // ------------------------------------------------------------ microphone

    private fun startMic(result: MethodChannel.Result) {
        if (!granted()) { result.error("permission", "Microphone permission not granted", null); return }
        if (micRunning) { result.success(MIC_RATE.toDouble()); return }

        val minBuf = AudioRecord.getMinBufferSize(MIC_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        if (minBuf <= 0) { result.error("mic_unavailable", "No microphone available", null); return }

        // UNPROCESSED bypasses AGC / noise suppression where the device
        // supports it (they smear the pitch); VOICE_RECOGNITION is the
        // closest fallback, plain MIC the last resort - some OEM builds
        // refuse the first two even though they advertise them.
        val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val unprocessed = "true" == am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED)
        val sources = ArrayList<Int>()
        if (unprocessed) sources.add(MediaRecorder.AudioSource.UNPROCESSED)
        sources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
        sources.add(MediaRecorder.AudioSource.MIC)

        var rec: AudioRecord? = null
        var lastError: String? = null
        for (source in sources) {
            val candidate = try {
                AudioRecord(source, MIC_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, max(minBuf, MIC_CHUNK * 4 * 4))
            } catch (e: Exception) {
                lastError = e.message; continue
            }
            if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                candidate.release(); lastError = "AudioRecord failed to initialise (source $source)"; continue
            }
            try {
                candidate.startRecording()
            } catch (e: Exception) {
                candidate.release(); lastError = e.message; continue
            }
            if (candidate.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                candidate.release(); lastError = "Microphone is busy"; continue
            }
            rec = candidate
            break
        }
        if (rec == null) {
            result.error("mic_unavailable", lastError ?: "No microphone available", null)
            return
        }
        val opened: AudioRecord = rec
        record = opened
        micRunning = true
        micThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buf = FloatArray(MIC_CHUNK)
            while (micRunning) {
                val n = opened.read(buf, 0, MIC_CHUNK, AudioRecord.READ_BLOCKING)
                if (n > 0) {
                    val copy = if (n == MIC_CHUNK) buf.copyOf() else buf.copyOf(n)
                    main.post { micSink?.success(copy) }
                } else if (n < 0) {
                    Log.w(TAG, "AudioRecord.read error $n")
                    emit(mapOf("type" to "error", "what" to "mic", "message" to "read error $n"))
                    break
                }
            }
        }, "tunekit-mic").also { it.start() }
        result.success(MIC_RATE.toDouble())
    }

    private fun stopMic() {
        micRunning = false
        val t = micThread
        micThread = null
        try { t?.join(500) } catch (_: InterruptedException) {}
        record?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        record = null
    }

    // ------------------------------------------------------------- metronome

    private inner class Metronome : AudioManager.OnAudioFocusChangeListener {
        @Volatile var bpm = 120
        @Volatile var beats = 4
        @Volatile var subPerBeat = 1
        @Volatile var accents: IntArray = intArrayOf(0)

        private var track: AudioTrack? = null
        private var thread: Thread? = null
        @Volatile private var running = false
        private var focusRequest: AudioFocusRequest? = null
        private val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val isPlaying: Boolean get() = running

        fun configure(call: MethodCall) {
            bpm = (call.argument<Int>("bpm") ?: 120).coerceIn(30, 300)
            beats = (call.argument<Int>("beats") ?: 4).coerceIn(1, 16)
            subPerBeat = (call.argument<Int>("subdivision") ?: 1).coerceIn(1, 4)
            val acc = call.argument<List<Int>>("accents")
            accents = if (acc.isNullOrEmpty()) intArrayOf(0) else acc.toIntArray()
        }

        fun start(): Boolean {
            if (running) return true
            val sr = AudioTrack.getNativeOutputSampleRate(AudioManager.STREAM_MUSIC).takeIf { it > 0 } ?: 48000
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            // Float + low latency first; fall back to a default-mode track,
            // then to 16-bit PCM - some devices refuse the float/low-latency
            // combination even though the API accepts it.
            var t: AudioTrack? = null
            var isFloat = true
            for (attempt in listOf(Pair(true, true), Pair(true, false), Pair(false, false))) {
                val built = buildTrack(sr, attrs, float = attempt.first, lowLatency = attempt.second) ?: continue
                t = built
                isFloat = attempt.first
                break
            }
            if (t == null) return false
            requestFocus(attrs)
            track = t
            running = true
            try { t.play() } catch (e: Exception) { Log.e(TAG, "play", e); t.release(); track = null; running = false; return false }
            thread = Thread({ renderLoop(t, sr, isFloat) }, "tunekit-metro").also { it.start() }
            return true
        }

        private fun buildTrack(sr: Int, attrs: AudioAttributes, float: Boolean, lowLatency: Boolean): AudioTrack? {
            val encoding = if (float) AudioFormat.ENCODING_PCM_FLOAT else AudioFormat.ENCODING_PCM_16BIT
            val minBuf = AudioTrack.getMinBufferSize(sr, AudioFormat.CHANNEL_OUT_MONO, encoding)
            if (minBuf <= 0) return null
            val format = AudioFormat.Builder()
                .setEncoding(encoding)
                .setSampleRate(sr)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val builder = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setBufferSizeInBytes(max(minBuf, 2048 * (if (float) 4 else 2)))
                .setTransferMode(AudioTrack.MODE_STREAM)
            if (lowLatency && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }
            val t = try { builder.build() } catch (e: Exception) { Log.w(TAG, "AudioTrack build failed (float=$float, lowLatency=$lowLatency)", e); return null }
            if (t.state != AudioTrack.STATE_INITIALIZED) { t.release(); return null }
            return t
        }

        fun stop(notify: Boolean) {
            if (!running && track == null) return
            running = false
            val th = thread
            thread = null
            try { th?.join(500) } catch (_: InterruptedException) {}
            track?.let {
                try { it.pause(); it.flush(); it.stop() } catch (_: Exception) {}
                it.release()
            }
            track = null
            abandonFocus()
            if (notify) emit(mapOf("type" to "interrupted", "what" to "metro"))
        }

        private fun requestFocus(attrs: AudioAttributes) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(this)
                    .build()
                focusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(this, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
        }

        private fun abandonFocus() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { am.abandonAudioFocusRequest(it) }
                focusRequest = null
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(this)
            }
        }

        override fun onAudioFocusChange(change: Int) {
            // A call or another player taking the output: stop and tell the
            // UI, rather than ticking silently or fighting for the speaker.
            if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                main.post { stop(notify = true) }
            }
        }

        private fun kindAt(tickIndex: Long): Int {
            val perBar = beats * subPerBeat
            val inBar = (tickIndex % perBar).toInt()
            if (inBar % subPerBeat != 0) return 2
            val beat = inBar / subPerBeat
            return if (accents.contains(beat)) 0 else 1
        }

        private fun beatAt(tickIndex: Long): Int {
            val perBar = beats * subPerBeat
            return (tickIndex % perBar).toInt() / subPerBeat
        }

        /** y(t) = g · sin(2π f t) · e^(−t/τ) — mirrors metronome_math.dart. */
        private fun click(t: Double, kind: Int): Float {
            val f = when (kind) { 0 -> 1760.0; 1 -> 1320.0; else -> 990.0 }
            val tau = if (kind == 0) 0.008 else 0.006
            val g = when (kind) { 0 -> 1.0; 1 -> 0.8; else -> 0.45 }
            return (g * sin(2 * PI * f * t) * exp(-t / tau)).toFloat()
        }

        private fun renderLoop(t: AudioTrack, sr: Int, isFloat: Boolean) {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val chunk = FloatArray(256)
            val shorts = if (isFloat) null else ShortArray(chunk.size)
            var pos = 0L
            var nextTick = 0.0
            var tickIndex = 0L
            val voices = ArrayList<Voice>(4)
            while (running) {
                for (i in chunk.indices) {
                    val p = pos + i
                    while (p >= nextTick) {
                        val kind = kindAt(tickIndex)
                        voices.add(Voice(p, kind))
                        val head = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
                        val dueMs = (p - head).coerceAtLeast(0) * 1000.0 / sr
                        emit(mapOf("type" to "tick", "index" to tickIndex, "beat" to beatAt(tickIndex), "kind" to kind, "dueMs" to dueMs))
                        tickIndex++
                        nextTick += sr * 60.0 / bpm / subPerBeat
                    }
                    var s = 0f
                    var v = 0
                    while (v < voices.size) {
                        val voice = voices[v]
                        val tt = (p - voice.start).toDouble() / sr
                        val len = if (voice.kind == 0) 0.040 else 0.030
                        if (tt > len) { voices.removeAt(v); continue }
                        s += click(tt, voice.kind)
                        v++
                    }
                    chunk[i] = s.coerceIn(-1f, 1f)
                }
                val written = if (shorts == null) {
                    t.write(chunk, 0, chunk.size, AudioTrack.WRITE_BLOCKING)
                } else {
                    for (i in chunk.indices) shorts[i] = (chunk[i] * 32767f).toInt().toShort()
                    t.write(shorts, 0, shorts.size, AudioTrack.WRITE_BLOCKING)
                }
                if (written < 0) {
                    Log.w(TAG, "AudioTrack.write error $written")
                    emit(mapOf("type" to "error", "what" to "metro", "message" to "write error $written"))
                    main.post { stop(notify = true) }
                    return
                }
                pos += chunk.size
            }
        }
    }
}
