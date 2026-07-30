package com.noobclaw.echojot

import android.Manifest
import android.annotation.TargetApi
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * On-device dictation bridge.
 *
 * Contract with the Dart side (lib/tool/dictation.dart):
 *  - `capabilities` -> map(onDevice, sdkInt, installedLanguages, supportedLanguages, detail)
 *  - `start`(language) / `stop`
 *  - events: {type: status|partial|final|level|error}
 *
 * Design rules, in order of importance:
 *  1. ONLY the on-device recognizer is ever created
 *     ([SpeechRecognizer.createOnDeviceSpeechRecognizer], API 31+). There is no
 *     cloud path in this file — that is the product promise, not an option.
 *  2. Long dictation: the system recognizer stops at every pause, so a session
 *     is a restart loop. Each finished utterance is emitted as `final` and, if
 *     the user is still dictating, listening restarts immediately.
 *  3. Never spin forever: repeated failures without any result stop the session
 *     with a visible error instead of looping silently.
 *  4. SpeechRecognizer is main-thread-only — every call here is posted to the
 *     main looper.
 */
class DictationBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private companion object {
        const val TAG = "EchoJotDictation"
        const val METHOD_CHANNEL = "echojot/dictation"
        const val EVENT_CHANNEL = "echojot/dictation/events"

        /** Consecutive failed listen cycles (no text at all) before giving up. */
        const val MAX_CONSECUTIVE_ERRORS = 4

        /**
         * A pause with no words is normal, but an engine that returns NO_MATCH
         * instantly (half-installed pack, mic held by a call) would otherwise
         * loop forever. Bound it by cycles and by wall time without any result.
         */
        const val MAX_BENIGN_CYCLES = 30
        const val MAX_QUIET_MS = 120_000L

        /** Small gap between utterances so the recognizer releases the mic. */
        const val RESTART_DELAY_MS = 150L

        /** Throttle for mic-level events: the meter animates over 140 ms anyway. */
        const val LEVEL_MIN_INTERVAL_MS = 80L

        /** Capability probe must never hang the settings screen. */
        const val PROBE_TIMEOUT_MS = 2500L

        // SpeechRecognizer.ERROR_LANGUAGE_* were added in API 33. Their values
        // are frozen platform constants; spelling them out keeps the release
        // build lint-clean on our API 31 floor.
        const val ERROR_LANGUAGE_NOT_SUPPORTED_COMPAT = 12
        const val ERROR_LANGUAGE_UNAVAILABLE_COMPAT = 13
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
        it.setStreamHandler(this)
    }

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    private var recognizer: SpeechRecognizer? = null
    private var language: String = "en-US"

    /** Only used for the API 33+ capability probe callback. */
    private var probeExecutor: ExecutorService? = null

    /**
     * Recognizer instances are swapped (start / rebuild) and a destroyed one can
     * still deliver a queued callback. Each listener carries the generation it
     * was attached with and ignores anything that arrives for an older one —
     * otherwise a late onResults duplicates a sentence and a late onError
     * derails a healthy session.
     */
    private var generation = 0

    /** True between `start` and `stop`: drives the restart loop. */
    private var sessionActive = false
    private var consecutiveErrors = 0

    /** Guards against two startListening calls landing on one recognizer. */
    private var listening = false

    /** Bounded-loop bookkeeping (see MAX_BENIGN_CYCLES / MAX_QUIET_MS). */
    private var benignCycles = 0
    private var lastProgressAt = 0L
    private var lastLevelAt = 0L

    /** Single restart runnable so a rescheduled restart replaces the pending one. */
    private val restartRunnable = Runnable { listenOrFail() }

    // ---------------------------------------------------------------- methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> reportCapabilities(result)
            "start" -> {
                language = call.argument<String>("language")?.takeIf { it.isNotBlank() }
                    ?: defaultLanguageTag()
                start(result)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun onDeviceAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        } catch (e: Throwable) {
            // Some OEM builds ship a stub — treat any failure as "unavailable"
            // rather than crashing or, worse, falling back to the network.
            Log.w(TAG, "isOnDeviceRecognitionAvailable failed", e)
            false
        }
    }

    /**
     * Probes the platform. On API 33+ we can also ask which on-device languages
     * are actually installed — used to label the UI honestly. The probe is
     * best-effort: any failure just means "unknown", never an error to the user.
     */
    private fun reportCapabilities(result: MethodChannel.Result) {
        val available = onDeviceAvailable()
        val payload = hashMapOf<String, Any?>(
            "onDevice" to available,
            "sdkInt" to Build.VERSION.SDK_INT,
            "installedLanguages" to emptyList<String>(),
            "supportedLanguages" to emptyList<String>(),
            "detail" to if (available) {
                "on-device recognizer available (API ${Build.VERSION.SDK_INT})"
            } else {
                "no on-device recognizer (API ${Build.VERSION.SDK_INT})"
            },
        )
        if (!available) {
            result.success(payload)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            probeLanguages(payload, result)
        } else {
            // API 31/32 cannot enumerate installed packs; the UI says so
            // instead of guessing.
            result.success(payload)
        }
    }

    @TargetApi(Build.VERSION_CODES.TIRAMISU)
    private fun probeLanguages(
        payload: HashMap<String, Any?>,
        result: MethodChannel.Result,
    ) {
        var replied = false
        val reply = {
            if (!replied) {
                replied = true
                result.success(payload)
            }
        }
        // Whatever the OEM recognizer does (including nothing), we answer.
        main.postDelayed({ reply() }, PROBE_TIMEOUT_MS)
        main.post {
            val probe = try {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } catch (e: Throwable) {
                Log.w(TAG, "probe recognizer creation failed", e)
                null
            }
            if (probe == null) {
                reply()
                return@post
            }
            val executor = probeExecutor
                ?: Executors.newSingleThreadExecutor().also { probeExecutor = it }
            try {
                probe.checkRecognitionSupport(
                    recognizerIntent(language),
                    executor,
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(support: RecognitionSupport) {
                            // This callback runs on `executor`; the payload is
                            // serialized on the main looper, so mutate it there
                            // too or the two can collide mid-reply.
                            val installed = support.installedOnDeviceLanguages
                            val supported = support.supportedOnDeviceLanguages
                            main.post {
                                payload["installedLanguages"] = installed
                                payload["supportedLanguages"] = supported
                                destroyQuietly(probe)
                                reply()
                            }
                        }

                        override fun onError(error: Int) {
                            main.post {
                                destroyQuietly(probe)
                                reply()
                            }
                        }
                    },
                )
            } catch (e: Throwable) {
                Log.w(TAG, "checkRecognitionSupport failed", e)
                destroyQuietly(probe)
                reply()
            }
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "RECORD_AUDIO not granted", null)
            return
        }
        if (!onDeviceAvailable()) {
            result.error(
                "on_device_unavailable",
                "No on-device speech recognition on this device",
                null,
            )
            return
        }
        main.post {
            try {
                releaseRecognizer()
                recognizer = createRecognizer()
                sessionActive = true
                consecutiveErrors = 0
                benignCycles = 0
                lastProgressAt = SystemClock.elapsedRealtime()
                // Report failure through the Result, never as "success" plus an
                // error event: the Dart side would otherwise show a live timer
                // for a session that does not exist.
                if (listenOnce()) {
                    result.success(null)
                } else {
                    sessionActive = false
                    releaseRecognizer()
                    result.error("recognizer_failed", "startListening failed", null)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "start failed", e)
                sessionActive = false
                releaseRecognizer()
                result.error("recognizer_failed", e.message, null)
            }
        }
    }

    private fun stop() {
        main.post {
            if (!sessionActive) {
                emit(mapOf("type" to "status", "value" to "stopped"))
                return@post
            }
            sessionActive = false
            main.removeCallbacks(restartRunnable)
            try {
                // stopListening() (not cancel) so the last utterance still comes
                // back through onResults.
                recognizer?.stopListening()
            } catch (e: Throwable) {
                Log.w(TAG, "stopListening failed", e)
            }
            // Free the recognizer once the final result has had its chance.
            main.postDelayed({ if (!sessionActive) releaseRecognizer() }, 1500)
            emit(mapOf("type" to "status", "value" to "stopped"))
        }
    }

    // createOnDeviceSpeechRecognizer is API 31 and minSdk is 31 — no guard needed.
    private fun createRecognizer(): SpeechRecognizer {
        generation++
        return SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            .also { it.setRecognitionListener(Listener(generation)) }
    }

    /** Returns false if the recognizer refused to start. */
    private fun listenOnce(): Boolean {
        val r = recognizer ?: return false
        if (!sessionActive) return false
        if (listening) return true // a restart already landed; don't double-start
        return try {
            r.startListening(recognizerIntent(language))
            listening = true
            emit(mapOf("type" to "status", "value" to "listening"))
            true
        } catch (e: Throwable) {
            Log.e(TAG, "startListening failed", e)
            false
        }
    }

    private fun listenOrFail() {
        if (!sessionActive) return
        if (!listenOnce()) {
            failSession("recognizer_failed", "startListening failed")
        }
    }

    /**
     * Schedules the next listen cycle. Engines that deliver both onError and
     * onResults for one utterance would otherwise queue two starts 150 ms apart
     * and earn an ERROR_RECOGNIZER_BUSY, so a pending restart is replaced.
     */
    private fun restartAfterUtterance() {
        if (!sessionActive) return
        main.removeCallbacks(restartRunnable)
        main.postDelayed(restartRunnable, RESTART_DELAY_MS)
    }

    private fun recognizerIntent(languageTag: String): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageTag)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Belt and braces: the recognizer is already on-device by
            // construction, and this makes the intent itself say so.
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        }

    private fun failSession(code: String, message: String) {
        sessionActive = false
        listening = false
        main.removeCallbacks(restartRunnable)
        releaseRecognizer()
        emit(mapOf("type" to "error", "code" to code, "message" to message))
        emit(mapOf("type" to "status", "value" to "stopped"))
    }

    private fun releaseRecognizer() {
        listening = false
        // Bump the generation so any callback still queued for the old instance
        // is recognised as stale.
        generation++
        recognizer?.let { destroyQuietly(it) }
        recognizer = null
    }

    private fun destroyQuietly(r: SpeechRecognizer) {
        try {
            r.cancel()
        } catch (_: Throwable) {
        }
        try {
            r.destroy()
        } catch (e: Throwable) {
            Log.w(TAG, "destroy failed", e)
        }
    }

    private fun defaultLanguageTag(): String =
        context.resources.configuration.locales[0]?.toLanguageTag() ?: "en-US"

    // ----------------------------------------------------------------- events

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            events?.success(event)
        } else {
            main.post { events?.success(event) }
        }
    }

    /** Called from the activity's onDestroy. */
    fun dispose() {
        sessionActive = false
        main.removeCallbacksAndMessages(null)
        releaseRecognizer()
        probeExecutor?.shutdownNow()
        probeExecutor = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        events = null
    }

    private inner class Listener(private val gen: Int) : RecognitionListener {
        /** Callbacks from a swapped-out recognizer must not touch this session. */
        private fun stale(): Boolean = gen != generation

        override fun onReadyForSpeech(params: Bundle?) {
            if (stale()) return
            emit(mapOf("type" to "status", "value" to "ready"))
        }

        override fun onBeginningOfSpeech() {}

        override fun onRmsChanged(rmsdB: Float) {
            if (stale()) return
            val now = SystemClock.elapsedRealtime()
            if (now - lastLevelAt < LEVEL_MIN_INTERVAL_MS) return
            lastLevelAt = now
            emit(mapOf("type" to "level", "db" to rmsdB.toDouble()))
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            if (stale()) return
            listening = false
            emit(mapOf("type" to "status", "value" to "endOfSpeech"))
        }

        override fun onError(error: Int) {
            if (stale()) return
            listening = false
            if (!sessionActive) {
                emit(mapOf("type" to "status", "value" to "stopped"))
                return
            }
            // A pause with no words is the normal way an utterance ends — keep
            // the session going, but bounded: an engine that fails instantly must
            // not spin invisibly (design rule 3).
            val benign = error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            if (benign) {
                benignCycles++
                val quietMs = SystemClock.elapsedRealtime() - lastProgressAt
                if (benignCycles >= MAX_BENIGN_CYCLES || quietMs > MAX_QUIET_MS) {
                    failSession(
                        "no_speech",
                        "no speech recognised in $benignCycles cycles / $quietMs ms",
                    )
                } else {
                    restartAfterUtterance()
                }
                return
            }
            when (error) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                    failSession("permission", "RECORD_AUDIO revoked")

                ERROR_LANGUAGE_NOT_SUPPORTED_COMPAT,
                ERROR_LANGUAGE_UNAVAILABLE_COMPAT,
                ->
                    failSession(
                        "on_device_unavailable",
                        "language pack not installed: $language",
                    )

                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                SpeechRecognizer.ERROR_CLIENT,
                SpeechRecognizer.ERROR_SERVER,
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                -> {
                    // Transient / wrong-engine errors: rebuild the recognizer a
                    // couple of times, then surface the failure.
                    consecutiveErrors++
                    if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                        failSession("recognizer_failed", "error $error")
                    } else {
                        rebuildAndListen()
                    }
                }

                else -> {
                    consecutiveErrors++
                    if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                        failSession("recognizer_failed", "error $error")
                    } else {
                        restartAfterUtterance()
                    }
                }
            }
        }

        override fun onResults(results: Bundle?) {
            if (stale()) return
            listening = false
            val text = firstResult(results)
            if (text.isNotBlank()) {
                consecutiveErrors = 0
                benignCycles = 0
                lastProgressAt = SystemClock.elapsedRealtime()
                emit(mapOf("type" to "final", "text" to text))
            }
            restartAfterUtterance()
        }

        override fun onPartialResults(partial: Bundle?) {
            if (stale()) return
            val text = firstResult(partial)
            if (text.isNotBlank()) {
                lastProgressAt = SystemClock.elapsedRealtime()
                emit(mapOf("type" to "partial", "text" to text))
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}

        private fun firstResult(bundle: Bundle?): String =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
    }

    private fun rebuildAndListen() {
        main.post {
            if (!sessionActive) return@post
            main.removeCallbacks(restartRunnable)
            listening = false
            releaseRecognizer()
            try {
                recognizer = createRecognizer()
                main.postDelayed(restartRunnable, RESTART_DELAY_MS * 2)
            } catch (e: Throwable) {
                Log.e(TAG, "rebuild failed", e)
                failSession("recognizer_failed", e.message ?: "rebuild failed")
            }
        }
    }
}
