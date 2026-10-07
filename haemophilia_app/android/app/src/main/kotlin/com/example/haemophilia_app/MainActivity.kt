package com.example.haemophilia_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("haemophilia_notifications", "Messages and sessions", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Messages from your care team and scheduled sessions"
            channel.enableVibration(true)
            channel.setShowBadge(true)
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            manager.createNotificationChannel(channel)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hemo/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "dismiss" -> {
                    val tag = call.argument<String>("id")
                    if (tag != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        manager.activeNotifications.filter { it.tag == tag }.forEach { manager.cancel(it.tag, it.id) }
                    }
                    result.success(null)
                }
                "dismissAll" -> { manager.cancelAll(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
