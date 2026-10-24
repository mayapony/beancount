package com.jindou.bean_count

import android.content.Context

/** 原生侧只需要知道「开关是否开启」；明细配置仍以 Flutter 的 app_state 为准。 */
object ScreenshotPrefs {
    private const val FILE = "screenshot_entry"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_LAST_FAILED_URI = "last_failed_uri"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    /**
     * 读取失败的截图 URI：点「读取截图失败」通知时用它把图重新取出来。
     *
     * 只留最后一条——用户点的是最新那条通知，积压多张也没有取回入口。
     */
    fun setLastFailedUri(context: Context, uri: String?) {
        val editor = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
        if (uri.isNullOrEmpty()) {
            editor.remove(KEY_LAST_FAILED_URI)
        } else {
            editor.putString(KEY_LAST_FAILED_URI, uri)
        }
        editor.apply()
    }

    /** 取走失败 URI（取一次就清空）。 */
    fun takeLastFailedUri(context: Context): String? {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val value = prefs.getString(KEY_LAST_FAILED_URI, null) ?: return null
        prefs.edit().remove(KEY_LAST_FAILED_URI).apply()
        return value
    }
}

/** 进程内共享状态：App 是否在前台（前台时不处理截图，避免截自己的界面）。 */
object ScreenshotRuntime {
    @Volatile
    var isAppVisible: Boolean = false
}
