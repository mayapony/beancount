package com.jindou.bean_count

import android.content.ContentUris
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log

/**
 * 监听 MediaStore 里新出现的截图。
 *
 * Android 14 的 ScreenCaptureCallback 只在本 App 可见时触发，覆盖不了
 * 「在支付宝/微信里截图」这个核心场景，所以全版本统一走 ContentObserver；
 * 代价是需要相册读权限（33+ READ_MEDIA_IMAGES，≤32 READ_EXTERNAL_STORAGE）。
 *
 * 关键点：**优先处理 onChange 给的那条 URI**。之前这里每次都按时间窗重新查
 * 「最新的一张截图」，当新截图的行还没进 MediaStore 时，会拿到上一张旧图，
 * 于是自动识别看起来「没认出金额」，而手动上传正确的图却正常。
 */
class ScreenshotWatcher(
    private val context: Context,
    private val onScreenshot: (Uri) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var registered = false
    private val retries = linkedMapOf<String, RetryTarget>()
    private var retryScheduled = false
    private val retryLoop = object : Runnable {
        override fun run() {
            retryScheduled = false
            if (retries.isEmpty()) return
            val batch = retries.values.toList()
            for (target in batch) {
                val result = if (target.recent) {
                    val row = queryRecentScreenshot()
                    QueryResult(found = row != null, row = row)
                } else {
                    target.uri?.let { queryUri(it) } ?: QueryResult(found = false)
                }
                when {
                    result.row != null -> {
                        retries.remove(target.key)
                        emit(result.row)
                    }
                    result.found -> retries.remove(target.key) // 行存在但不是截图
                    target.attempt + 1 >= MAX_RETRIES -> retries.remove(target.key)
                    else -> target.attempt += 1
                }
            }
            if (retries.isNotEmpty()) scheduleRetryLoop()
        }
    }
    private val processed: LinkedHashSet<String> =
        LinkedHashSet(
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(KEY_PROCESSED, emptySet())
                .orEmpty(),
        )

    /**
     * 正在读取/识别的截图：挡住同一张图的并发回调。
     *
     * 与 [processed] 的区别：失败后会被释放，允许发布后的二次回调重试；
     * [processed] 只在**读取成功后**才写入。
     */
    private val inFlight: MutableSet<String> = mutableSetOf()

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            maybeEmit(uri)
        }
    }

    fun start() {
        if (registered) return
        try {
            context.contentResolver.registerContentObserver(
                imageCollectionUri(),
                true,
                observer,
            )
            registered = true
        } catch (error: Exception) {
            Log.w(TAG, "注册截图监听失败", error)
        }
    }

    fun stop() {
        handler.removeCallbacks(retryLoop)
        retryScheduled = false
        retries.clear()
        if (!registered) return
        try {
            context.contentResolver.unregisterContentObserver(observer)
        } catch (error: Exception) {
            Log.w(TAG, "注销截图监听失败", error)
        }
        registered = false
    }

    /**
     * [uri] 来自 ContentObserver：通常是新图片的 item URI，也可能是集合 URI。
     * 优先查这条 URI；查不到再退回「最近几秒内新增的截图」，并短重试几次。
     */
    private fun maybeEmit(uri: Uri?) {
        if (ScreenshotRuntime.isAppVisible) return

        if (uri != null && isItemUri(uri)) {
            val result = queryUri(uri)
            if (result.row != null) {
                emit(result.row)
                return
            }
            // 行已经存在但不是截图（比如用户保存的照片）：不要拿旧截图凑数
            if (result.found) return
            // 行还没进 MediaStore：加入重试队列，绝不退回「最新一张」
            scheduleRetry(uri, recent = false)
            return
        }

        val recent = queryRecentScreenshot()
        if (recent != null) {
            emit(recent)
            return
        }
        scheduleRetry(uri, recent = true)
    }

    private fun emit(row: MediaRow) {
        val key = row.uri.toString()
        if (processed.contains(key) || inFlight.contains(key)) return
        inFlight.add(key)
        Log.i(TAG, "检测到截图：${row.name}（pending=${row.pending}，$key）")
        onScreenshot(row.uri)
    }

    /**
     * 服务处理完一张截图后回报结果（主线程）。
     *
     * 只有**读取成功**才写入 [processed]；读取失败/超时只释放 [inFlight]，
     * 让发布后再次到来的变更通知有机会重试——这正是「pending 期间读不到，
     * 发布后再也回不来」那个 bug 的修复点。
     */
    fun markHandled(uri: Uri, readSucceeded: Boolean) {
        val key = uri.toString()
        handler.post {
            inFlight.remove(key)
            if (readSucceeded && processed.add(key)) persistProcessed()
        }
    }

    /**
     * 该条目是否已发布（不再 pending）。
     *
     * `null` 表示查不到状态（旧系统、查询失败或行已消失），调用方按「未知」
     * 处理、退回直接尝试读取，而不是当失败。
     */
    fun isPublished(uri: Uri): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.IS_PENDING),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) null else cursor.getInt(0) == 0
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 重试用队列而不是单个 Runnable：连续截图时，前一张的重试不能被后一张顶掉。
     * item URI 固定查自己；集合 URI/null 才查最近几秒。
     */
    private fun scheduleRetry(uri: Uri?, recent: Boolean) {
        val key = if (recent || uri == null) "recent" else uri.toString()
        retries.putIfAbsent(key, RetryTarget(key, uri, recent))
        scheduleRetryLoop()
    }

    private fun scheduleRetryLoop() {
        if (retryScheduled) return
        retryScheduled = true
        handler.postDelayed(retryLoop, RETRY_MS)
    }

    private fun queryUri(uri: Uri): QueryResult {
        return try {
            context.contentResolver.query(uri, projection(), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use QueryResult(found = false)
                    QueryResult(
                        found = true,
                        row = rowFromCursor(cursor, uri),
                    )
                } ?: QueryResult(found = false)
        } catch (error: SecurityException) {
            Log.w(TAG, "没有相册读权限，跳过本次截图")
            QueryResult(found = false)
        } catch (error: Exception) {
            Log.w(TAG, "查询截图 URI 失败", error)
            QueryResult(found = false)
        }
    }

    private fun queryRecentScreenshot(): MediaRow? {
        val since = System.currentTimeMillis() / 1000 - FALLBACK_WINDOW_SECONDS
        val selection = "${MediaStore.Images.Media.DATE_ADDED} >= ?"
        val args = arrayOf(since.toString())
        val sort = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        return try {
            context.contentResolver.query(
                imageCollectionUri(),
                projection(),
                selection,
                args,
                sort,
            )?.use { cursor ->
                var checked = 0
                while (cursor.moveToNext() && checked < MAX_ROWS) {
                    checked++
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                    val row = rowFromCursor(
                        cursor,
                        ContentUris.withAppendedId(imageCollectionUri(), id),
                    ) ?: continue
                    return@use row
                }
                null
            }
        } catch (error: SecurityException) {
            // 没有相册读权限：静默（设置页会提示去授权）
            Log.w(TAG, "没有相册读权限，跳过本次截图")
            null
        } catch (error: Exception) {
            Log.w(TAG, "查询截图失败", error)
            null
        }
    }

    private fun rowFromCursor(cursor: android.database.Cursor, uri: Uri): MediaRow? {
        val name = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
            .takeIf { it >= 0 }
            ?.let { cursor.getString(it) }
            .orEmpty()
        val dateAdded = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
            .takeIf { it >= 0 }
            ?.let { cursor.getLong(it) }
            ?: 0L
        val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
        } else {
            cursor.getColumnIndex(MediaStore.Images.Media.DATA)
        }.takeIf { it >= 0 }?.let { cursor.getString(it) }.orEmpty()
        val pending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            cursor.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
                .takeIf { it >= 0 }
                ?.let { cursor.getInt(it) != 0 } ?: false
        } else {
            false
        }

        if (dateAdded > 0) {
            val age = System.currentTimeMillis() / 1000 - dateAdded
            if (age > MAX_AGE_SECONDS) {
                Log.d(TAG, "跳过旧图片：$name（${age}秒）")
                return null
            }
        }
        if (!looksLikeScreenshot(name, path)) return null
        return MediaRow(uri = uri, name = name, pending = pending)
    }

    private fun isItemUri(uri: Uri): Boolean =
        uri.lastPathSegment?.toLongOrNull() != null ||
            uri.pathSegments.lastOrNull()?.toLongOrNull() != null

    private fun imageCollectionUri(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    private fun projection(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.RELATIVE_PATH,
                MediaStore.Images.Media.IS_PENDING,
            )
        } else {
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DATA,
            )
        }

    private fun looksLikeScreenshot(name: String, path: String): Boolean {
        val haystack = "$path/$name".lowercase()
        return SCREENSHOT_HINTS.any { haystack.contains(it) }
    }

    /** 已处理路径落盘，服务重启后也不会把同一张截图再识别一遍。 */
    private fun persistProcessed() {
        if (processed.size > MAX_STORED) {
            val toRemove = processed.take(processed.size - MAX_STORED).toList()
            processed.removeAll(toRemove.toSet())
        }
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(KEY_PROCESSED, processed)
                .apply()
        } catch (error: Exception) {
            Log.w(TAG, "保存已处理截图失败", error)
        }
    }

    private data class MediaRow(
        val uri: Uri,
        val name: String,
        val pending: Boolean = false,
    )

    private data class QueryResult(val found: Boolean, val row: MediaRow? = null)

    private data class RetryTarget(
        val key: String,
        val uri: Uri?,
        val recent: Boolean,
        var attempt: Int = 0,
    )

    companion object {
        private const val TAG = "ScreenshotWatcher"
        private const val PREFS_NAME = "screenshot_watcher"
        private const val KEY_PROCESSED = "processed_uris"
        private const val MAX_STORED = 200
        private const val RETRY_MS = 250L
        private const val MAX_RETRIES = 12
        private const val MAX_AGE_SECONDS = 30L

        /** 只查最近几秒的截图，避免重试时又拿到上一张旧图。 */
        private const val FALLBACK_WINDOW_SECONDS = 5L
        private const val MAX_ROWS = 5
        private val SCREENSHOT_HINTS = listOf(
            "screenshot",
            "screen_shot",
            "screen shot",
            "screencap",
            "screen_capture",
            "screen-",
            "screenshots",
            "截图",
            "截屏",
        )
    }
}
