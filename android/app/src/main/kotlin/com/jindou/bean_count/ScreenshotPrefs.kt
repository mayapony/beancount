package com.jindou.bean_count

import android.content.Context

/** 原生侧只需要知道「开关是否开启」；明细配置仍以 Flutter 的 app_state 为准。 */
object ScreenshotPrefs {
    private const val FILE = "screenshot_entry"
    private const val KEY_ENABLED = "enabled"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }
}

/** 进程内共享状态：App 是否在前台（前台时不处理截图，避免截自己的界面）。 */
object ScreenshotRuntime {
    @Volatile
    var isAppVisible: Boolean = false
}
