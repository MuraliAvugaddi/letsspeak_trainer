package com.speakwithsurendratrainer.app

import android.util.Log
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 🎤 VOICE GATE — cleans OUR OWN mic on the phone, before the sound is sent.
 *
 * The phone's noise filter removes steady noise (fan, AC), but not far-away
 * people talking, TV, traffic, a pin drop… and the mic's auto-volume makes
 * those LOUD whenever the speaker stops for a moment.
 *
 * This gate listens to every 10 ms of mic sound:
 *   • the speaker's own (close) voice  → passes 100 %
 *   • between words / sentences        → room sound pushed down to ~12 % (-18 dB)
 *   • far voices / background          → are much quieter than a close voice,
 *                                         so they stay pushed down
 * It opens at once (no first-word cut) and closes softly 0.3 s after speech.
 *
 * Runs inside WebRTC's own audio chain (after its echo / noise filter), so the
 * trainer and all students hear the cleaned voice. Works for students AND
 * trainers. Nothing is sent to any server; no extra internet.
 */
object VoiceGate {
    private const val TAG = "VoiceGate"

    // ---- tuning ----
    private const val FLOOR_GAIN = 0.12f // not speaking → -18 dB
    private const val ABOVE_NOISE_DB = 9.0 // speech must be ≥ 9 dB over the room noise
    private const val BELOW_VOICE_DB = 22.0 // …and not more than 22 dB under the speaker's voice
    private const val MIN_OPEN_DB = -58.0 // very quiet room: still need a real sound
    private const val HOLD_FRAMES = 30 // keep open 300 ms after the last word sound
    private const val RELEASE = 0.93f // closes over ~0.3 s (no clicks)

    @Volatile
    var enabled = true

    private var proxy: Any? = null
    private var adapter: Any? = null

    // audio-thread state
    private var floorDb = -60.0
    private var voiceDb = -24.0
    private var gain = 1f
    private var hold = 0

    /** Add the gate to WebRTC's mic chain (safe to call many times). */
    @Synchronized
    fun install(): Boolean {
        return try {
            val pluginCls = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            val plugin = pluginCls.getField("sharedSingleton").get(null) ?: return false
            val ctrl = pluginCls.getMethod("getAudioProcessingController").invoke(plugin) ?: return false
            val ad = ctrl.javaClass.getField("capturePostProcessing").get(ctrl) ?: return false
            if (ad === adapter && proxy != null) return true // already in this chain

            val iface = Class.forName(
                "com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter\$ExternalAudioFrameProcessing"
            )
            val handler = InvocationHandler { self, m, args ->
                when (m.name) {
                    "initialize", "reset" -> {
                        resetState(); null
                    }
                    "process" -> {
                        try {
                            process(args!![1] as Int, args[2] as ByteBuffer)
                        } catch (_: Throwable) {
                        }
                        null
                    }
                    "hashCode" -> System.identityHashCode(self)
                    "equals" -> self === args?.getOrNull(0)
                    "toString" -> "VoiceGate"
                    else -> null
                }
            }
            val p = Proxy.newProxyInstance(iface.classLoader, arrayOf(iface), handler)
            ad.javaClass.getMethod("addProcessor", iface).invoke(ad, p)
            proxy = p
            adapter = ad
            resetState()
            Log.i(TAG, "voice gate ON")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "voice gate not available: $e")
            false
        }
    }

    private fun resetState() {
        floorDb = -60.0
        voiceDb = -24.0
        gain = 1f
        hold = 0
    }

    private fun process(numFrames: Int, raw: ByteBuffer) {
        val buf = raw.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val n = min(numFrames, buf.capacity())
        if (n <= 0) return
        if (!enabled) {
            gain = 1f
            return
        }

        // loudness of these 10 ms (samples are in the 16-bit range)
        var sum = 0.0
        for (i in 0 until n) {
            val s = buf.get(i).toDouble()
            sum += s * s
        }
        val db = 20.0 * log10(max(sqrt(sum / n), 1.0) / 32768.0)

        // room noise: follows quiet moments fast, rises slowly (~3 dB / s)
        floorDb = if (db < floorDb) floorDb + (db - floorDb) * 0.3 else floorDb + 0.03
        // speaker's voice level: rises over ~0.1 s of real speech (one bang
        // does not count), falls very slowly (~0.5 dB / s → remembered for a long time)
        voiceDb = if (db > voiceDb) voiceDb + (db - voiceDb) * 0.1 else max(voiceDb - 0.005, floorDb + 15.0)

        val openAt = max(max(floorDb + ABOVE_NOISE_DB, voiceDb - BELOW_VOICE_DB), MIN_OPEN_DB)
        if (db > openAt) hold = HOLD_FRAMES else if (hold > 0) hold--

        val target = if (hold > 0) 1f else FLOOR_GAIN
        val next = if (target > gain) target else max(target, gain * RELEASE)
        if (gain >= 0.999f && next >= 0.999f) {
            gain = 1f
            return // speaking → untouched
        }
        // smooth change inside the 10 ms (no clicks)
        val step = (next - gain) / n
        var g = gain
        for (i in 0 until n) {
            g += step
            buf.put(i, buf.get(i) * g)
        }
        gain = next
    }
}
