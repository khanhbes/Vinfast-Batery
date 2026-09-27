package com.vinfast.vinfast_battery

import android.os.Build
import com.bes.vinbatery.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
