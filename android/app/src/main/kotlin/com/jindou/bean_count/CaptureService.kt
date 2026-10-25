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
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.Locale

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
                "notifyEntry" -> {
                    val cents = (call.argument<Number>("amount_cents"))?.toLong() ?: 0L
                    val note = call.argument<String>("note")?.trim().orEmpty()
                    Log.i(TAG, "notifyEntry amount=$cents note=$note")
                    showEntryNotification(cents, note)
                    result.success(null)
                }
                "log" -> {
                    Log.i(TAG, call.argument<String>("message").orEmpty())
                    result.success(null)
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
        manager.createNotificationChannel(
            NotificationChannel(
                ENTRY_CHANNEL_ID,
                "自动记账结果",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "支付后自动入账的提醒；只做视觉提示，不响铃不振动"
                setSound(null, null)
                enableVibration(false)
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

    /** 已记账通知：深链到「最近自动记账」列表，点开直接核对。 */
    private fun showEntryNotification(cents: Long, note: String) {
        val amount = String.format(Locale.CHINA, "%.2f", cents / 100.0)
        val text = if (note.isEmpty()) "已记账 ¥$amount" else "已记账 ¥$amount · $note"
        val notification = NotificationCompat.Builder(this, ENTRY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("金豆 · 自动记账")
            .setContentText(text)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setContentIntent(openAutoEntriesIntent())
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(ENTRY_NOTIFICATION_ID, notification)
    }

    private fun openAutoEntriesIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN_AUTO_ENTRIES, true)
        }
        return PendingIntent.getActivity(
            this,
            ENTRY_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val CHANNEL = "com.jindou.bean_count/capture"
        const val EXTRA_OPEN_AUTO_ENTRIES = "open_auto_entries"
        private const val TAG = "BeanCapture"
        private const val CHANNEL_ID = "capture_service"
        private const val ENTRY_CHANNEL_ID = "capture_entry"
        private const val ONGOING_ID = 51
        private const val ENTRY_NOTIFICATION_ID = 52
        private const val ENTRY_REQUEST_CODE = 110

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
