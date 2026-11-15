package com.jindou.bean_count

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 开机后恢复监听（只在用户开启过对应开关时）。 */
class ScreenshotBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        // 两个通道共用一个前台服务：任一开关开着就拉起来
        if (ScreenshotPrefs.isEnabled(context) || CapturePrefs.isEnabled(context)) {
            CaptureHostService.start(context)
        }
    }
}
