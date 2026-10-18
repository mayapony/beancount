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
 */
class ScreenshotWatcher(
    private val context: Context,
    private val onScreenshot: (Uri) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var registered = false
    private var lastUri: Uri? = null
    private var lastAt = 0L
    private var lastQueryAt = 0L

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            maybeEmit()
        }
    }

    fun start() {
        if (registered) return
        try {
            context.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                observer,
            )
            registered = true
        } catch (error: Exception) {
            Log.w(TAG, "注册截图监听失败", error)
        }
    }

    fun stop() {
        if (!registered) return
        try {
            context.contentResolver.unregisterContentObserver(observer)
        } catch (error: Exception) {
            Log.w(TAG, "注销截图监听失败", error)
        }
        registered = false
    }

    private fun maybeEmit() {
        val now = System.currentTimeMillis()
        // 一次截屏会连续触发多条通知，先按时间粗筛
        if (now - lastQueryAt < BURST_MS) return
        lastQueryAt = now
        if (ScreenshotRuntime.isAppVisible) return

        val row = queryLatestScreenshot(now) ?: return
        if (row.uri == lastUri && now - lastAt < DEDUPE_MS) return
        lastUri = row.uri
        lastAt = now
        Log.i(TAG, "检测到截图：${row.name}")
        onScreenshot(row.uri)
    }

    private fun queryLatestScreenshot(now: Long): MediaRow? {
        val since = now / 1000 - 10
        val resolver = context.contentResolver
        val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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
        val selection = "${MediaStore.Images.Media.DATE_ADDED} >= ?"
        val args = arrayOf(since.toString())
        val sort = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        try {
            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                args,
                sort,
            )?.use { cursor ->
                var checked = 0
                while (cursor.moveToNext() && checked < MAX_ROWS) {
                    checked++
                    val id = cursor.getLong(0)
                    val name = cursor.getString(1) ?: ""
                    val path = cursor.getString(3) ?: ""
                    if (!looksLikeScreenshot(name, path)) continue
                    return MediaRow(
                        uri = ContentUris.withAppendedId(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            id,
                        ),
                        name = name,
                    )
                }
            }
        } catch (error: SecurityException) {
            // 没有相册读权限：静默（设置页会提示去授权）
            Log.w(TAG, "没有相册读权限，跳过本次截图")
        } catch (error: Exception) {
            Log.w(TAG, "查询截图失败", error)
        }
        return null
    }

    private fun looksLikeScreenshot(name: String, path: String): Boolean {
        val haystack = "$path/$name".lowercase()
        return SCREENSHOT_HINTS.any { haystack.contains(it) }
    }

    private data class MediaRow(val uri: Uri, val name: String)

    companion object {
        private const val TAG = "ScreenshotWatcher"
        private const val BURST_MS = 400L
        private const val DEDUPE_MS = 10_000L
        private const val MAX_ROWS = 5
        private val SCREENSHOT_HINTS = listOf(
            "screenshot",
            "screen_shot",
            "screencap",
            "screen_capture",
            "screen-",
            "screenshots",
            "截图",
        )
    }
}
