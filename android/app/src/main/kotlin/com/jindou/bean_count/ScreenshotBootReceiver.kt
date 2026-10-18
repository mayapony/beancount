package com.jindou.bean_count

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 开机后恢复监听（只在用户开启过开关时）。 */
class ScreenshotBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!ScreenshotPrefs.isEnabled(context)) return
        ScreenshotService.start(context)
    }
}
