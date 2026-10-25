package com.jindou.bean_count

import android.content.Context

/**
 * 自动记账的原生开关、挂起标记与「已认识」的包集合。
 *
 * 「已认识」包替换了原来的硬编码白名单：默认只带微信 / 支付宝两个种子，之后
 * 用户在哪个 App 上截图记了一笔，就把那个包名加进来，以后只对这些包持续抓树 /
 * 监听通知。明细配置仍以 Flutter 的 app_state 为准。
 */
object CapturePrefs {
    private const val FILE = "capture_entry"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_PENDING_OPEN = "pending_open_auto_entries"
    private const val KEY_KNOWN_PACKAGES = "known_packages"

    /** 出厂种子：微信、支付宝。之后自动增长，不再硬编码维护。 */
    private val seedPackages = setOf(
        "com.tencent.mm",
        "com.eg.android.AlipayGphone",
    )

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

    /** 当前「已认识」的包集合（种子 + 截图学到的）。 */
    fun knownPackages(context: Context): Set<String> {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val stored = prefs.getStringSet(KEY_KNOWN_PACKAGES, null)
        return if (stored == null) {
            prefs.edit().putStringSet(KEY_KNOWN_PACKAGES, seedPackages).apply()
            seedPackages
        } else {
            stored + seedPackages
        }
    }

    fun isKnown(context: Context, packageName: String): Boolean =
        knownPackages(context).contains(packageName)

    /** 把一个新认识的包加进集合（截图兜底学会时调用）。 */
    fun addKnown(context: Context, packageName: String) {
        val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val updated = (knownPackages(context) + packageName).toSet()
        prefs.edit().putStringSet(KEY_KNOWN_PACKAGES, updated).apply()
    }
}
