package com.example.letsspeak_trainer

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🛟 live class: keep running in the background + list Bluetooth / headphones
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "letsspeak/class_service")
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
     *  phoneCall: normal SIM call (ringing / talking)
     *  voipCall : WhatsApp / other app call (another app is using the mic for a call)
     */
    private fun callState(myMicOn: Boolean): Map<String, Any> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val mode = am.mode
        val phoneCall = mode == AudioManager.MODE_RINGTONE ||
            mode == AudioManager.MODE_IN_CALL ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && mode == AudioManager.MODE_CALL_SCREENING)
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
