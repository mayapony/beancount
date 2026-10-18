package com.jindou.bean_count

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.ByteArrayOutputStream
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

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
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

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
        ioExecutor.shutdownNow()
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
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "screenshotEntry",
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
        showProgress()
        // 读图和压缩都放到后台线程：ContentObserver 的回调在主线程，
        // 大截图 + Bitmap 压缩直接做会卡住通知栏/服务。
        ioExecutor.execute {
            val original = readCompleteImage(uri)
            if (original == null) {
                mainHandler.post {
                    showResult("读取截图失败 · 点击手动记", ok = false)
                }
                return@execute
            }
            val recognition = compressForRecognition(original) ?: original
            Log.i(
                TAG,
                "识别图片：原图 ${original.size / 1024}KB，" +
                    "识别图 ${recognition.size / 1024}KB（$uri）",
            )
            mainHandler.post {
                val methodChannel = channel ?: return@post
                methodChannel.invokeMethod(
                    "recognize",
                    mapOf(
                        "bytes" to original,
                        "recognitionBytes" to recognition,
                        "path" to uri.toString(),
                    ),
                    recognizeResult(),
                )
            }
        }
    }

    /** ContentObserver 的通知可能早于文件写完：轮询到大小/尾部有效为止。 */
    private fun readCompleteImage(uri: Uri): ByteArray? {
        val expected = querySize(uri)
        val deadline = System.currentTimeMillis() + READ_TIMEOUT_MS
        var last: ByteArray? = null
        var lastError: Exception? = null
        while (true) {
            val bytes = try {
                contentResolver.openInputStream(uri)?.use { it.readBytes() }
            } catch (error: Exception) {
                // 截图刚插入时可能是 pending/trashed，稍后重试即可；最后再统一记日志
                lastError = error
                null
            }
            if (bytes != null && bytes.isNotEmpty()) {
                last = bytes
                val sizeReady = expected <= 0L || bytes.size >= expected
                if (sizeReady && looksComplete(bytes)) return bytes
            }
            if (System.currentTimeMillis() >= deadline) break
            try {
                Thread.sleep(READ_POLL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
        if (last == null) {
            Log.w(TAG, "读取截图失败", lastError)
        } else {
            Log.w(TAG, "截图可能不完整，按已读到的 ${last.size} 字节继续")
        }
        return last
    }

    private fun querySize(uri: Uri): Long {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
                ?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
        } catch (_: Exception) {
            0L
        }
    }

    /** JPEG 看 EOI，PNG 看 IEND；其它格式只要求非空。 */
    private fun looksComplete(bytes: ByteArray): Boolean {
        if (bytes.size < 4) return false
        if (bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()) {
            return bytes.size >= 4 &&
                bytes[bytes.size - 2] == 0xFF.toByte() &&
                bytes[bytes.size - 1] == 0xD9.toByte()
        }
        if (bytes.size >= 12 &&
            bytes[0] == 0x89.toByte() &&
            bytes[1] == 'P'.code.toByte()
        ) {
            val tail = String(bytes, bytes.size - 8, 4, Charsets.ISO_8859_1)
            return tail == "IEND"
        }
        return true
    }

    /**
     * 识别副本：最长边压到 1920、JPEG 85，和 BeeCount 的做法一致。
     * 原图仍随草稿落盘；模型只收识别副本，避免窄长截图被模型按总像素
     * 二次缩小后字更糊。
     */
    private fun compressForRecognition(bytes: ByteArray): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longest / (sample * 2) >= MAX_DIMENSION) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null

        val scale = minOf(1f, MAX_DIMENSION.toFloat() / maxOf(decoded.width, decoded.height))
        val targetWidth = maxOf(1, (decoded.width * scale).roundToInt())
        val targetHeight = maxOf(1, (decoded.height * scale).roundToInt())
        val scaled = if (targetWidth == decoded.width && targetHeight == decoded.height) {
            decoded
        } else {
            Bitmap.createScaledBitmap(decoded, targetWidth, targetHeight, true)
        }
        return try {
            ByteArrayOutputStream().use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, RECOGNITION_QUALITY, out)
                out.toByteArray().takeIf { it.isNotEmpty() }
            }
        } finally {
            if (scaled !== decoded) scaled.recycle()
            decoded.recycle()
        }
    }

    private fun recognizeResult(): MethodChannel.Result = object : MethodChannel.Result {
        override fun success(result: Any?) {
            val map = result as? Map<*, *>
            if (map?.get("ok") == true) {
                val cents = (map["amount_cents"] as? Number)?.toLong() ?: 0L
                showResult("已识别 ¥${money(cents)} · 点击记账", ok = true)
            } else {
                val reason = (map?.get("error") as? String)?.trim().orEmpty()
                val text = if (reason.isEmpty() || reason.contains("没认出金额")) {
                    "没认出金额 · 点击手动记"
                } else {
                    "$reason · 点击手动记"
                }
                showResult(text, ok = false)
            }
        }

        override fun error(code: String, message: String?, details: Any?) {
            showResult("识别失败 · 点击手动记", ok = false)
        }

        override fun notImplemented() {
            showResult("识别失败 · 点击手动记", ok = false)
        }
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
        private const val READ_TIMEOUT_MS = 3_000L
        private const val READ_POLL_MS = 100L
        private const val MAX_DIMENSION = 1920
        private const val RECOGNITION_QUALITY = 85

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
