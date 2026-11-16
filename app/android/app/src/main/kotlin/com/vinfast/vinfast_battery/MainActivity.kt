package com.vinfast.vinfast_battery

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.bes.vinbatery.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // flutter_background_service defaults autoStartOnBoot to true. Older
        // builds persisted that value, which can revive a second Flutter
        // engine while the login splash is still starting. Trips configure
        // and start the service explicitly when the user begins tracking.
        getSharedPreferences("id.flutter.background_service", MODE_PRIVATE)
            .edit()
            .putBoolean("auto_start_on_boot", false)
            .apply()

        // flutter_background_service may be restarted by its watchdog before
        // Dart startup reaches NotificationService.initialize(). Create the
        // channel natively first so Android can accept the FGS notification.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "vinfast_bg_channel",
                "VinFast Battery",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Background service status"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
        super.onCreate(savedInstanceState)
        preferHighRefreshRate()
    }

    /**
     * QA 141: the OnePlus 9 Pro screen runs at 120 Hz but Pinova was drawn
     * at 60 Hz (ColorOS keeps apps at 60 unless they ask). Ask for the
     * fastest mode at the current resolution; the system may still lower it
     * (battery saver, heat).
     */
    private fun preferHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate } ?: return
        if (best.refreshRate <= current.refreshRate + 1f) return
        window.attributes = window.attributes.apply {
            preferredDisplayModeId = best.modeId
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vinfast.battery/splash")
            .setMethodCallHandler { call, result ->
                if (call.method != "setSplashTheme") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val style = when (call.arguments as? String) {
                    "light" -> R.style.LaunchThemeLight
                    "dark" -> R.style.LaunchThemeDark
                    else -> R.style.LaunchThemeSystem
                }
                splashScreen.setSplashScreenTheme(style)
                result.success(null)
            }

        // QA 161: "Cài đặt mạng" on the offline notice opens the phone's
        // network settings; the owner changes them, the app never does.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vinfast.battery/settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "network") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val opened = try {
                    startActivity(
                        Intent(Settings.ACTION_WIRELESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    true
                } catch (_: Exception) {
                    false
                }
                result.success(opened)
            }

        // QA 151: two short chimes (charge started / finished). Sonification
        // usage: the phone's silent and vibrate modes mute them.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.vinfast.battery/feedback")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val id = feedbackSounds()[call.arguments as? String]
                if (id != null) feedbackPool?.play(id, 0.6f, 0.6f, 1, 0, 1f)
                result.success(null)
            }
    }

    private var feedbackPool: SoundPool? = null
    private var feedbackIds: Map<String, Int> = emptyMap()

    /** Loaded on first use and kept: SoundPool plays only decoded samples. */
    private fun feedbackSounds(): Map<String, Int> {
        if (feedbackPool != null) return feedbackIds
        val pool = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        feedbackPool = pool
        feedbackIds = mapOf(
            "charge_start" to pool.load(this, R.raw.charge_start, 1),
            "charge_done" to pool.load(this, R.raw.charge_done, 1),
        )
        return feedbackIds
    }

    override fun onDestroy() {
        feedbackPool?.release()
        feedbackPool = null
        super.onDestroy()
    }
}
