package com.speakwithsurendratrainer.app

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // 📺 class as a small window over WhatsApp / other apps (only while in class)
    //    (kept in the companion object → still known if Android re-opens this screen)
    private var classChannel: MethodChannel? = null

    // ---------------------------------------------------------------
    // 🛟 The app (and the live class inside it) lives in ONE Flutter engine that
    // survives when Android closes this screen (small window closed, phone
    // cleaning memory, Oppo / Vivo / Realme "optimisation", back button...).
    // Before: screen closed → engine closed → class gone + app started from the
    // splash again (trainer had to log in again). Now: screen comes back → same
    // class, same page, nothing restarts.
    // ---------------------------------------------------------------
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        cache.put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    companion object {
        private const val ENGINE_ID = "letsspeak_main"
        private var pipWanted = false
    }

    override fun onResume() {
        super.onResume()
        updatePip() // screen re-opened → small window setting again
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🛟 live class: keep running in the background + list Bluetooth / headphones
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "letsspeak/class_service")
        classChannel = channel
        channel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            ClassAudioService.start(
                                applicationContext,
                                call.argument<String>("title") ?: "Live class",
                                call.argument<String>("text") ?: "Your class is running."
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stop" -> {
                        ClassAudioService.stop(applicationContext)
                        result.success(true)
                    }
                    "pip" -> {
                        pipWanted = call.argument<Boolean>("on") == true
                        updatePip()
                        result.success(true)
                    }
                    "outputs" -> result.success(soundDevices())
                    "callState" -> result.success(callState(call.argument<Boolean>("micOn") == true))
                    "restoreMode" -> {
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            if (am.mode == AudioManager.MODE_NORMAL) am.mode = AudioManager.MODE_IN_COMMUNICATION
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 📞 Is the phone in a call?
     *  phoneCall: normal SIM call — only once it is ANSWERED (ringing → class keeps going,
     *             so the person can say "wait, I have a call", mute and then pick up)
     *  voipCall : WhatsApp / other app call (another app is using the mic for a call)
     */
    private fun callState(myMicOn: Boolean): Map<String, Any> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val mode = am.mode
        val phoneCall = mode == AudioManager.MODE_IN_CALL
        var voipCall = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val calls = am.activeRecordingConfigurations.count {
                    it.clientAudioSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION
                }
                // my own class mic counts as 1 → more than that = another app's call
                voipCall = calls > (if (myMicOn) 1 else 0)
            } catch (_: Exception) {}
        }
        return mapOf("mode" to mode, "phoneCall" to phoneCall, "voipCall" to voipCall)
    }

    // ---------------------------------------------------------------
    // 📺 SMALL WINDOW (picture-in-picture), Android 8+
    // Android 12+: goes small by itself when the person leaves the app.
    // Android 8–11: onUserLeaveHint (home button / recent apps) makes it small.
    // ---------------------------------------------------------------
    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(Rational(3, 2))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(pipWanted)
            b.setSeamlessResizeEnabled(false)
        }
        return b.build()
    }

    private fun updatePip() {
        if (!pipSupported()) return
        try {
            pipParams()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {}
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipWanted || !pipSupported() || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        try {
            pipParams()?.let { enterPictureInPictureMode(it) }
        } catch (_: Exception) {}
    }

    // 📺 Back swipe / back button on the HOME page while a class is running:
    // before → the app just disappeared into the background (class still playing,
    // but nothing on screen). Now → the class becomes the small window, same as
    // pressing the Home button. Not in class → normal back (app closes).
    override fun popSystemNavigator(): Boolean {
        if (pipWanted && pipSupported()) {
            try {
                val params = pipParams()
                if (params != null && enterPictureInPictureMode(params)) return true
            } catch (_: Exception) {}
        }
        return false
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        try {
            classChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
        } catch (_: Exception) {}
    }

    /** Connected Bluetooth / wired headphones → [{type, name}] */
    private fun soundDevices(): List<Map<String, String>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val out = mutableListOf<Map<String, String>>()
        val seen = mutableSetOf<String>()
        for (d in am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            val type = when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "headset"
                else -> when {
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && d.type == AudioDeviceInfo.TYPE_USB_HEADSET -> "headset"
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && d.type == AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
                    else -> null
                }
            } ?: continue
            val name = d.productName?.toString() ?: ""
            if (seen.add("$type|$name")) out.add(mapOf("type" to type, "name" to name))
        }
        return out
    }
}
