package com.jindou.bean_count

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * 原生侧的运行记录：Dart 还没起来时（引擎未就绪 / 服务未启动 / 窗口读不到）
 * 唯一的落笔处。
 *
 * 两处落盘：
 * - `SharedPreferences("capture_diag")` 里一份环形（[MAX_EVENTS] 条），诊断页读它；
 * - `files/diag/events.log` 追加一行 JSON，adb 直接 pull。
 *
 * 写失败一律吞掉：记录不能影响采集与入账。
 */
object CaptureDiag {

    private const val PREFS = "capture_diag"
    private const val KEY_EVENTS = "events"
    private const val KEY_RUNNING = "service_running"
    private const val KEY_STARTED_AT = "service_started_at"
    private const val KEY_STOPPED_AT = "service_stopped_at"

    private const val LOG_DIR = "diag"
    private const val LOG_NAME = "events.log"
    private const val LOG_MAX_BYTES = 512 * 1024

    const val MAX_EVENTS = 100

    /** 文件写入丢到单线程，别让无障碍事件的主线程碰磁盘。 */
    private val writer = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "capture-diag-writer").apply { isDaemon = true }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * 记一条事件。[detail] 只放简单值（字符串 / 数字 / 布尔 / 简单数组），
     * 会被原样塞进 JSON。
     */
    @Synchronized
    fun record(
        context: Context,
        kind: String,
        packageName: String? = null,
        target: String? = null,
        ok: Boolean = true,
        reason: String? = null,
        detail: Map<String, Any?> = emptyMap(),
    ) {
        try {
            val at = System.currentTimeMillis()
            val event = JSONObject().apply {
                put("seq", at)
                put("at", isoOf(at))
                put("kind", kind)
                if (packageName != null) put("package", packageName)
                if (target != null) put("target", target)
                put("ok", ok)
                if (reason != null) put("reason", reason)
                if (detail.isNotEmpty()) put("detail", JSONObject(detail))
                put("count", 1)
            }
            appendToRing(context, event.toString())
            appendToFile(context, event.toString())
        } catch (_: Throwable) {
            // 记录失败不影响任何业务
        }
    }

    /** 诊断页读取：环形里的全部事件，按写入顺序。 */
    fun readAll(context: Context): String = prefs(context).getString(KEY_EVENTS, "[]") ?: "[]"

    /** 记录后台服务的启动 / 停止，供诊断页判断「服务到底在不在跑」。 */
    @Synchronized
    fun setServiceRunning(context: Context, running: Boolean) {
        val at = System.currentTimeMillis()
        val editor = prefs(context).edit().putBoolean(KEY_RUNNING, running)
        if (running) {
            editor.putLong(KEY_STARTED_AT, at).putLong(KEY_STOPPED_AT, 0L)
        } else {
            editor.putLong(KEY_STOPPED_AT, at)
        }
        editor.apply()
    }

    fun serviceState(context: Context): Map<String, Any?> {
        val prefs = prefs(context)
        return mapOf(
            "running" to prefs.getBoolean(KEY_RUNNING, false),
            "started_at" to prefs.getLong(KEY_STARTED_AT, 0L),
            "stopped_at" to prefs.getLong(KEY_STOPPED_AT, 0L),
        )
    }

    @Synchronized
    fun clear(context: Context) {
        try {
            prefs(context).edit().remove(KEY_EVENTS).apply()
            val dir = logDir(context) ?: return
            File(dir, LOG_NAME).delete()
            File(dir, "$LOG_NAME.1").delete()
        } catch (_: Throwable) {
            // 清空失败无害
        }
    }

    private fun appendToRing(context: Context, line: String) {
        val prefs = prefs(context)
        val array = try {
            JSONArray(prefs.getString(KEY_EVENTS, "[]") ?: "[]")
        } catch (_: Throwable) {
            JSONArray()
        }
        array.put(JSONObject(line))
        while (array.length() > MAX_EVENTS) {
            array.remove(0)
        }
        prefs.edit().putString(KEY_EVENTS, array.toString()).apply()
    }

    private fun appendToFile(context: Context, line: String) {
        val dir = logDir(context) ?: return
        writer.execute {
            try {
                val file = File(dir, LOG_NAME)
                if (file.exists() && file.length() > LOG_MAX_BYTES) {
                    val rolled = File(dir, "$LOG_NAME.1")
                    rolled.delete()
                    file.renameTo(rolled)
                }
                file.appendText(line + "\n")
            } catch (_: Throwable) {
                // 落盘失败不影响业务
            }
        }
    }

    /** `Android/data/<包名>/files/diag`，adb 能直接 pull；取不到外部目录退回内部。 */
    private fun logDir(context: Context): File? = try {
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        File(base, LOG_DIR).apply { mkdirs() }
    } catch (_: Throwable) {
        null
    }

    private fun isoOf(at: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }.format(Date(at))
}
