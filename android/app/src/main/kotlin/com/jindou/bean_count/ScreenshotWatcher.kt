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
    private var retryRunnable: Runnable? = null
    private val processed: LinkedHashSet<String> =
        LinkedHashSet(
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(KEY_PROCESSED, emptySet())
                .orEmpty(),
        )

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            maybeEmit(uri, attempt = 0)
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
        retryRunnable?.let { handler.removeCallbacks(it) }
        retryRunnable = null
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
    private fun maybeEmit(uri: Uri?, attempt: Int) {
        if (ScreenshotRuntime.isAppVisible) return

        if (uri != null && isItemUri(uri)) {
            val result = queryUri(uri)
            if (result.row != null) {
                emit(result.row)
                return
            }
            // 行已经存在但不是截图（比如用户保存的照片）：不要拿旧截图凑数
            if (result.found) return
            // 行还没进 MediaStore：继续重试，绝不退回「最新一张」
            if (attempt < MAX_RETRIES) scheduleRetry(uri, attempt + 1)
            return
        }

        val recent = queryRecentScreenshot()
        if (recent != null) {
            emit(recent)
            return
        }
        if (attempt < MAX_RETRIES) scheduleRetry(uri, attempt + 1)
    }

    private fun emit(row: MediaRow) {
        val key = row.uri.toString()
        if (!processed.add(key)) return
        persistProcessed()
        Log.i(TAG, "检测到截图：${row.name}（$key）")
        onScreenshot(row.uri)
    }

    private fun scheduleRetry(uri: Uri?, attempt: Int) {
        retryRunnable?.let { handler.removeCallbacks(it) }
        val runnable = Runnable {
            retryRunnable = null
            maybeEmit(uri, attempt)
        }
        retryRunnable = runnable
        handler.postDelayed(runnable, RETRY_MS)
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

        if (dateAdded > 0) {
            val age = System.currentTimeMillis() / 1000 - dateAdded
            if (age > MAX_AGE_SECONDS) {
                Log.d(TAG, "跳过旧图片：$name（${age}秒）")
                return null
            }
        }
        if (!looksLikeScreenshot(name, path)) return null
        return MediaRow(uri = uri, name = name)
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

    private data class MediaRow(val uri: Uri, val name: String)

    private data class QueryResult(val found: Boolean, val row: MediaRow? = null)

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
