package com.weiyalong.naidianji

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feed_reminder/system_ui")
            .setMethodCallHandler { call, result ->
                if (call.method != "setSystemBarsHidden") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val hidden = call.arguments as? Boolean
                if (hidden == null) {
                    result.error("invalid_arguments", "Expected a boolean visibility value.", null)
                    return@setMethodCallHandler
                }

                // Hide bars without opting out of the required edge-to-edge layout.
                val controller = WindowCompat.getInsetsController(window, window.decorView)
                if (hidden) {
                    controller.systemBarsBehavior =
                        WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(WindowInsetsCompat.Type.systemBars())
                } else {
                    controller.show(WindowInsetsCompat.Type.systemBars())
                }
                result.success(null)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "feed_reminder/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "openNotificationSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val settingsIntents = mutableListOf<Intent>()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    settingsIntents.add(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                }
                // Older Android versions and some vendors only expose app details.
                settingsIntents.add(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ),
                )
                for (intent in settingsIntents) {
                    try {
                        startActivity(intent)
                        result.success(null)
                        return@setMethodCallHandler
                    } catch (_: ActivityNotFoundException) {
                        // Try the application details fallback.
                    } catch (_: SecurityException) {
                        // A vendor may restrict the notification settings activity.
                    }
                }
                result.error(
                    "notification_settings_unavailable",
                    "Unable to open notification settings.",
                    null,
                )
            }
    }
}
