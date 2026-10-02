package com.vinfast.vinfast_battery

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
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
    }
}
