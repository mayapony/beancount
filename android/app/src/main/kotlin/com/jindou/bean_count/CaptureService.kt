package com.jindou.bean_count

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * 常驻前台服务：宿主 headless FlutterEngine 跑 `captureEntry`。
 *
 * 无障碍 / 通知服务抓到的事件经 [CaptureRuntime] 交到这里，再由 Dart 侧做
 * 规则匹配 → 候选去重 → 入账。业务逻辑全在 Dart，这里只有引擎与通道。
 */
class CaptureService : Service() {
    private var engine: FlutterEngine? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        createEngine()
        startForeground(ONGOING_ID, ongoingNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        engine?.destroy()
        engine = null
        CaptureRuntime.channel = null
        CaptureRuntime.dartReady = false
        super.onDestroy()
    }

    private fun createEngine() {
        val flutterEngine = FlutterEngine(applicationContext)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "captureEntry",
            ),
        )
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    CaptureRuntime.dartReady = true
                    result.success(null)
                }
                "recentSnapshot" -> {
                    val pkg = call.argument<String>("package")
                    val snapshot = pkg?.let { CaptureRuntime.recentSnapshot(it) }
                    result.success(
                        if (snapshot == null) null else mapOf(
                            "package" to snapshot.packageName,
                            "dump" to snapshot.dump,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
        CaptureRuntime.channel = channel
        engine = flutterEngine
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "自动记账监听",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持无障碍 / 通知自动记账运行；关闭开关后消失"
            },
        )
    }

    private fun ongoingNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("正在自动记账")
            .setContentText("支付后自动入账；点此管理")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val CHANNEL = "com.jindou.bean_count/capture"
        private const val CHANNEL_ID = "capture_service"
        private const val ONGOING_ID = 51

        fun start(context: Context) {
            val intent = Intent(context, CaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureService::class.java))
        }
    }
}
