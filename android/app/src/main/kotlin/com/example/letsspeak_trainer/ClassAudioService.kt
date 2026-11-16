package com.example.letsspeak_trainer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 🛟 Keeps the live class running while the app is in the background
 * (another app open, WhatsApp, phone call, screen off).
 *
 * Android stops the microphone and may cut the network of apps in the
 * background. A foreground service with a small "Live class is on"
 * notification tells Android: this app is in a call — keep it alive.
 */
class ClassAudioService : Service() {

    companion object {
        private const val CHANNEL_ID = "live_class"
        private const val NOTIFICATION_ID = 4711

        fun start(context: Context, title: String, text: String) {
            val i = Intent(context, ClassAudioService::class.java)
                .putExtra("title", title)
                .putExtra("text", text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ClassAudioService::class.java))
        }
    }

    // 🔋 power button pressed (screen off) → keep CPU + Wi-Fi awake so the
    // class sound and mic don't stop
    private var cpuLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    private fun holdAwake() {
        try {
            if (cpuLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                cpuLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "letsspeak:liveclass").apply {
                    setReferenceCounted(false)
                    acquire(4 * 60 * 60 * 1000L) // max 4 hours (safety)
                }
            }
        } catch (_: Exception) {}
        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wm.createWifiLock(mode, "letsspeak:liveclass").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (_: Exception) {}
    }

    private fun releaseAwake() {
        try { cpuLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        cpuLock = null
        wifiLock = null
    }

    override fun onDestroy() {
        releaseAwake()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Live class"
        val text = intent?.getStringExtra("text") ?: "Your class is running."
        val notification = buildNotification(title, text)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                // microphone + sound playing → mic keeps working in the background
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } catch (e: Exception) {
                // no mic permission yet → at least keep the class sound playing
                try {
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                } catch (_: Exception) {
                    stopSelf()
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        holdAwake()
        // killed by the system → don't restart by itself (the app joins again when opened)
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // app swiped away from recent apps → class is over for this phone
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(CHANNEL_ID, "Live class", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shows while you are in a live class"
            channel.setSound(null, null)
            channel.enableVibration(false)
            manager.createNotificationChannel(channel)
        }

        // tap the notification → back to the app (the class screen is still open)
        val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val pending = open?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setShowWhen(false)
        if (pending != null) builder.setContentIntent(pending)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_CALL)
        }
        return builder.build()
    }
}
