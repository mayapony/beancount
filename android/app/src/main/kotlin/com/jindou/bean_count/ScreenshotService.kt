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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
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

    /** 读取循环在 IO 线程里查 pending 状态，所以这里要跨线程可见。 */
    @Volatile
    private var watcher: ScreenshotWatcher? = null
    private var dartReady = false
    private var queuedUri: Uri? = null
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 识别中 + 排队中的任务数；通知里的「还有 N 张」用它算排队项。 */
    private val busyJobs = AtomicInteger(0)

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
                "lastTreeSnapshot" -> {
                    val tree = CaptureRuntime.requestCurrentTree()
                    Log.i(TAG, "lastTreeSnapshot -> ${tree?.first ?: "null"}")
                    result.success(
                        if (tree == null) null else mapOf(
                            "package" to tree.first,
                            "dump" to tree.second,
                        ),
                    )
                }
                "addKnown" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg != null) CapturePrefs.addKnown(this, pkg)
                    result.success(null)
                }
                "lastNotification" -> {
                    val pkg = call.argument<String>("package")
                    val snapshot = pkg?.let { CaptureRuntime.lastNotification(it) }
                    Log.i(TAG, "lastNotification($pkg) -> ${snapshot?.text?.take(40) ?: "null"}")
                    result.success(snapshot?.text)
                }
                "log" -> {
                    Log.i(TAG, call.argument<String>("message").orEmpty())
                    result.success(null)
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
        // 检测到截图就立刻给反馈：队列空闲时马上亮「识别中」，用户不用等读图。
        // 排队中的截图等轮到自己再更新（processRecognize 开头），避免把上一张的
        // 结果盖掉后看不到。
        val wasIdle = busyJobs.getAndIncrement() == 0
        if (wasIdle) mainHandler.post { showProgress() }
        try {
            ioExecutor.execute {
                try {
                    processRecognize(uri, announceProgress = !wasIdle)
                } finally {
                    busyJobs.decrementAndGet()
                }
            }
        } catch (_: RejectedExecutionException) {
            busyJobs.decrementAndGet()
        }
    }

    private fun processRecognize(uri: Uri, announceProgress: Boolean) {
        if (announceProgress) mainHandler.post { showProgress() }

        val original = readPublishedImage(uri)
        if (original == null) {
            // 读不到：释放 in-flight 但不写 processed，发布后的二次回调还能重试；
            // 同时记下 URI，让「点击手动记」能把这张图重新取出来。
            watcher?.markHandled(uri, readSucceeded = false)
            ScreenshotPrefs.setLastFailedUri(this, uri.toString())
            mainHandler.post {
                showResult("读取截图失败 · 点击手动记", ok = false, recoverable = true)
            }
            return
        }
        watcher?.markHandled(uri, readSucceeded = true)

        val recognition = compressForRecognition(original) ?: original
        Log.i(
            TAG,
            "识别图片：原图 ${original.size / 1024}KB，" +
                "识别图 ${recognition.size / 1024}KB（$uri）",
        )

        // 单线程 executor + 等回调：一次只跑一个模型请求，避免连拍时
        // 请求并发、结果乱序和 429。
        val latch = CountDownLatch(1)
        val posted = mainHandler.post {
            val methodChannel = channel
            if (methodChannel == null) {
                latch.countDown()
                return@post
            }
            methodChannel.invokeMethod(
                "recognize",
                mapOf(
                    "bytes" to original,
                    "recognitionBytes" to recognition,
                    "path" to uri.toString(),
                ),
                recognizeResult(latch),
            )
        }
        if (posted) {
            try {
                latch.await(RECOGNITION_WAIT_SECONDS, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
                // 服务销毁
            }
        }
    }

    /**
     * 读取一张**已发布**的截图字节。
     *
     * MIUI 等厂商的截图服务会先在 MediaStore 插一条 pending 行，发布之前非属主
     * App 打不开（`Only owner is able to interact with pending/trashed item`），
     * 而厂商发布通常要 2–5 秒。所以这里先查 `IS_PENDING`：没发布就等，发布后
     * 再 open——pending 是正常的中间态，不是读取失败。
     */
    private fun readPublishedImage(uri: Uri): ByteArray? {
        val startedAt = System.currentTimeMillis()
        val deadline = startedAt + READ_TIMEOUT_MS
        var last: ByteArray? = null
        var lastError: Exception? = null
        var publishedAfterMs = 0L
        var pendingSinceMs = 0L

        while (true) {
            val published = watcher?.isPublished(uri)
            if (published == true) {
                if (pendingSinceMs > 0L) {
                    publishedAfterMs = System.currentTimeMillis() - pendingSinceMs
                    pendingSinceMs = 0L
                }
                val readStartedAt = System.currentTimeMillis()
                val bytes = try {
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                } catch (error: Exception) {
                    lastError = error
                    null
                }
                if (bytes != null && bytes.isNotEmpty()) {
                    last = bytes
                    val expected = querySize(uri)
                    val sizeReady = expected <= 0L || bytes.size >= expected
                    if (sizeReady && looksComplete(bytes)) {
                        Log.i(
                            TAG,
                            "读取截图：等待发布=${publishedAfterMs}ms " +
                                "读取=${System.currentTimeMillis() - readStartedAt}ms " +
                                "大小=${bytes.size / 1024}KB（$uri）",
                        )
                        return bytes
                    }
                }
            } else if (pendingSinceMs == 0L) {
                // false = 还没发布；null = 查不到状态。两种都从这一刻开始计等待。
                pendingSinceMs = System.currentTimeMillis()
            }
            if (System.currentTimeMillis() >= deadline) break
            try {
                Thread.sleep(READ_POLL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }

        val waited = System.currentTimeMillis() - startedAt
        when {
            last != null -> Log.w(
                TAG,
                "截图可能不完整，按已读到的 ${last.size} 字节继续（等待 ${waited}ms，$uri）",
            )
            pendingSinceMs > 0L -> Log.w(
                TAG,
                "等待发布超时：${waited}ms 后仍是 pending（$uri）",
            )
            lastError != null -> Log.w(TAG, "读取截图异常（${waited}ms，$uri）", lastError)
            else -> Log.w(TAG, "读取截图为空（${waited}ms，$uri）")
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

    private fun recognizeResult(latch: CountDownLatch): MethodChannel.Result =
        object : MethodChannel.Result {
            override fun success(result: Any?) {
                val map = result as? Map<*, *>
                val pending = (map?.get("pending_count") as? Number)
                    ?.toInt()?.coerceAtLeast(0) ?: 0
                // busyJobs 包含当前这一条；它之后还在排队的截图也要算给用户
                val queued = (busyJobs.get() - 1).coerceAtLeast(0)
                if (map?.get("ok") == true) {
                    val cents = (map["amount_cents"] as? Number)?.toLong() ?: 0L
                    if (map["auto_saved"] == true) {
                        val detail = listOfNotNull(
                            (map["category"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                            (map["account"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                        ).joinToString(" · ")
                        val base = if (map["duplicate"] == true) {
                            "这笔已经记过了 · ¥${money(cents)}"
                        } else {
                            "已自动记账 ¥${money(cents)}" +
                                if (detail.isEmpty()) "" else " · $detail"
                        }
                        showResult("$base${remainingSuffix(pending, queued)}", ok = true)
                    } else {
                        val rest = (pending - 1 + queued).coerceAtLeast(0)
                        val suffix = if (rest > 0) {
                            " · 还有 $rest 张待确认"
                        } else {
                            " · 点击记账"
                        }
                        showResult("已识别 ¥${money(cents)}$suffix", ok = true)
                    }
                } else {
                    val reason = (map?.get("error") as? String)?.trim().orEmpty()
                    val text = if (reason.isEmpty() || reason.contains("没认出金额")) {
                        "没认出金额"
                    } else {
                        reason
                    }
                    val suffix = if (pending + queued == 0) {
                        " · 点击手动记"
                    } else {
                        remainingSuffix(pending, queued)
                    }
                    showResult("$text$suffix", ok = false)
                }
                latch.countDown()
            }

            override fun error(code: String, message: String?, details: Any?) {
                showResult("识别失败 · 点击手动记", ok = false)
                latch.countDown()
            }

            override fun notImplemented() {
                showResult("识别失败 · 点击手动记", ok = false)
                latch.countDown()
            }
        }

    /** 队列里可能有已识别待确认的，也有还在处理的；分开说清楚。 */
    private fun remainingSuffix(pending: Int, queued: Int): String {
        val parts = mutableListOf<String>()
        if (pending > 0) parts.add("$pending 张待确认")
        if (queued > 0) parts.add("$queued 张处理中")
        return if (parts.isEmpty()) "" else " · 还有 " + parts.joinToString("、")
    }

    private fun showProgress() {
        notify(
            RESULT_ID,
            resultNotification("已截屏 · 识别中…", ongoing = true, progress = true),
        )
    }

    private fun showResult(text: String, ok: Boolean, recoverable: Boolean = false) {
        notify(
            RESULT_ID,
            resultNotification(
                text,
                ongoing = false,
                progress = false,
                ok = ok,
                recoverable = recoverable,
            ),
        )
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
            // 高优先级 + 静音：检测到截图就悬浮提示一下，能立刻察觉，但不响不震。
            // 旧渠道 screenshot_result 创建后无法由代码提权，所以另起一个渠道 ID；
            // 已安装设备上的旧渠道会继续留在系统设置里（渠道不可删除），不再使用。
            NotificationChannel(
                ALERT_CHANNEL,
                "截屏识别结果",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "检测到截屏与识别结果；只做视觉提示，不响铃不振动"
                setSound(null, null)
                enableVibration(false)
            },
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
        recoverable: Boolean = false,
    ): Notification {
        val builder = NotificationCompat.Builder(this, ALERT_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("金豆 · 截屏记账")
            .setContentText(text)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(openAppIntent(withRecovery = recoverable))
        // 识别中的进度条静音；结果弹悬浮（heads-up），更显眼。
        if (ongoing) {
            builder.setSilent(true)
            if (progress) builder.setProgress(0, 0, true)
        } else {
            builder.setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
        }
        return builder.build()
    }

    private fun openAppIntent(withRecovery: Boolean = false): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // 通知就是入口：用户点它时，让前台 Shell 消费待确认队列；
            // App 未打开时由启动/恢复流程自己消费。
            putExtra(EXTRA_CONSUME_PENDING, true)
            if (withRecovery) putExtra(EXTRA_RECOVER_SCREENSHOT, true)
        }
        return PendingIntent.getActivity(
            this,
            if (withRecovery) RECOVERY_REQUEST_CODE else NOTIFICATION_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun money(cents: Long): String =
        String.format(Locale.CHINA, "%.2f", cents / 100.0)

    companion object {
        const val CHANNEL = "com.jindou.bean_count/screenshot"
        const val EXTRA_CONSUME_PENDING = "consume_pending"

        /** 点「读取截图失败」通知时，把失败的 URI 重新读出来交给 Dart。 */
        const val EXTRA_RECOVER_SCREENSHOT = "recover_screenshot"
        private const val TAG = "ScreenshotService"
        private const val ONGOING_CHANNEL = "screenshot_service"
        private const val ALERT_CHANNEL = "screenshot_alert"
        private const val ONGOING_ID = 41
        private const val RESULT_ID = 42
        private const val NOTIFICATION_REQUEST_CODE = 100
        private const val RECOVERY_REQUEST_CODE = 101

        /**
         * 等厂商发布截图的上限。
         *
         * 本机（小米）实测发布耗时 2.16s / 3.60s；3.6s 那次就刚好越过旧的 3s 上限，
         * 于是同一张图「后台识别失败、手动上传却能认」。留一倍余量取 10s。
         */
        private const val READ_TIMEOUT_MS = 10_000L
        private const val READ_POLL_MS = 100L
        private const val RECOGNITION_WAIT_SECONDS = 60L
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
