package com.jindou.bean_count

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * 通知监听：白名单包发来通知时，把标题 + 正文拼成文本交给 [CaptureRuntime]。
 *
 * 通知文本通常自带「支付 ¥12.50」「收款 ¥100」这类金额线索，规则（LLM 生成的
 * 文本正则）在 Dart 侧套用；这里只做采集，不解析。
 */
class NotificationCaptureService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val packageName = sbn.packageName ?: return
        if (!CaptureWhitelist.contains(packageName)) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString().orEmpty()
        val text = extras.getCharSequence("android.text")?.toString().orEmpty()
        val content = listOf(title, text).filter { it.isNotBlank() }.joinToString("\n")
        if (content.isBlank()) return

        CaptureRuntime.onNotificationCaptured(packageName, content)
    }
}
