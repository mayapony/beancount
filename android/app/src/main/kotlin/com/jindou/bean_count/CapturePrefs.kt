package com.jindou.bean_count

import android.content.Context

/**
 * 自动记账的原生开关与「点通知打开列表」的挂起标记。
 *
 * 无障碍 / 通知服务是否已授权由系统设置决定，原生这里只记「用户开了总开关」；
 * 明细配置仍以 Flutter 的 app_state 为准。
 */
object CapturePrefs {
    private const val FILE = "capture_entry"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_PENDING_OPEN = "pending_open_auto_entries"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
    }

    /** 用户点了「已记账」通知、但 App 尚未就绪：先挂起，等 Shell 来取。 */
    fun setPendingOpenAutoEntries(context: Context, value: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PENDING_OPEN, value)
            .apply()
    }

    /** 取走挂起标记（取一次就清空）。 */
    fun takePendingOpenAutoEntries(context: Context): Boolean {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val value = prefs.getBoolean(KEY_PENDING_OPEN, false)
        if (value) prefs.edit().remove(KEY_PENDING_OPEN).apply()
        return value
    }
}
