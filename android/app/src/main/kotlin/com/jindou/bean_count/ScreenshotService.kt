package com.jindou.bean_count

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.Locale

/**
 * 常驻前台服务：监听截图 → 交给 headless FlutterEngine 识别 → 更新通知。
 *
 * 为什么用 headless engine：识别器、解析与配额都在 Dart 侧，重写一遍 Kotlin 版本
 * 会形成第二套规则。引擎在服务里常驻，App 被划掉后仍能识别。
 */
class ScreenshotService : Service() {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var watcher: ScreenshotWatcher? = null
    private var dartReady = false
    private var queuedUri: Uri? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        createEngine()
        startForeground(ONGOING_ID, ongoingNotification())
        watcher = ScreenshotWatcher(this) { uri -> handleScreenshot(uri) }.also { it.start() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        watcher?.stop()
        watcher = null
        engine?.destroy()
        engine = null
        channel = null
        super.onDestroy()
    }

    private fun createEngine() {
        val flutterEngine = FlutterEngine(applicationContext)
        try {
            GeneratedPluginRegistrant.registerWith(flutterEngine)
        } catch (error: Exception) {
            Log.w(TAG, "注册插件失败", error)
        }
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                "screenshotEntry",
                "package:bean_count/screenshot_entry.dart",
            ),
        )
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    dartReady = true
                    result.success(null)
                    queuedUri?.let { uri ->
                        queuedUri = null
                        recognize(uri)
                    }
                }
                else -> result.notImplemented()
            }
        }
        engine = flutterEngine
        channel = methodChannel
    }

    private fun handleScreenshot(uri: Uri) {
        if (!dartReady) {
            queuedUri = uri
            return
        }
        recognize(uri)
    }

    private fun recognize(uri: Uri) {
        val bytes = try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (error: Exception) {
            Log.w(TAG, "读取截图失败", error)
            null
        }
        if (bytes == null) {
            showResult("读取截图失败 · 点击手动记", ok = false)
            return
        }
        showProgress()
        channel?.invokeMethod(
            "recognize",
            mapOf("bytes" to bytes, "path" to uri.toString()),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val map = result as? Map<*, *>
                    if (map?.get("ok") == true) {
                        val cents = (map["amount_cents"] as? Number)?.toLong() ?: 0L
                        showResult("已识别 ¥${money(cents)} · 点击记账", ok = true)
                    } else {
                        showResult("没认出金额 · 点击手动记", ok = false)
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    showResult("识别失败 · 点击手动记", ok = false)
                }

                override fun notImplemented() {
                    showResult("识别失败 · 点击手动记", ok = false)
                }
            },
        )
    }

    private fun showProgress() {
        notify(
            RESULT_ID,
            resultNotification("已截屏 · 识别中…", ongoing = true, progress = true),
        )
    }

    private fun showResult(text: String, ok: Boolean) {
        notify(RESULT_ID, resultNotification(text, ongoing = false, progress = false, ok = ok))
    }

    private fun notify(id: Int, notification: Notification) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(id, notification)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                ONGOING_CHANNEL,
                "截屏监听",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持截屏监听运行；关闭开关后消失"
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                RESULT_CHANNEL,
                "截屏识别结果",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    private fun ongoingNotification(): Notification {
        return NotificationCompat.Builder(this, ONGOING_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("正在监听截屏")
            .setContentText("截屏后会自动识别；点此管理")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun resultNotification(
        text: String,
        ongoing: Boolean,
        progress: Boolean,
        ok: Boolean = true,
    ): Notification {
        return NotificationCompat.Builder(this, RESULT_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("金豆 · 截屏记账")
            .setContentText(text)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .apply { if (progress) setProgress(0, 0, true) }
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            100,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun money(cents: Long): String =
        String.format(Locale.CHINA, "%.2f", cents / 100.0)

    companion object {
        const val CHANNEL = "com.jindou.bean_count/screenshot"
        private const val TAG = "ScreenshotService"
        private const val ONGOING_CHANNEL = "screenshot_service"
        private const val RESULT_CHANNEL = "screenshot_result"
        private const val ONGOING_ID = 41
        private const val RESULT_ID = 42

        fun start(context: Context) {
            val intent = Intent(context, ScreenshotService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenshotService::class.java))
        }
    }
}
