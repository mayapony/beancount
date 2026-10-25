package com.jindou.bean_count

import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * 进程内共享的捕获总线：无障碍 / 通知服务把抓到的事件交给它，
 * [CaptureService] 里的 headless 引擎再把它们转发给 Dart。
 *
 * 同时维护最近 60 秒的树快照环形缓冲，供「截图留证 → 生成规则」时取回
 * 支付发生那一刻的控件树。
 */
object CaptureRuntime {

    @Volatile
    var channel: MethodChannel? = null

    @Volatile
    var dartReady: Boolean = false

    /** 无障碍服务实例（`onServiceConnected` 时挂上），供截图兜底一次性现读树。 */
    @Volatile
    var accessibilityService: AccessibilityCaptureService? = null

    private val snapshots = CopyOnWriteArrayList<TreeSnapshot>()
    private val notifications = CopyOnWriteArrayList<NotificationSnapshot>()

    data class TreeSnapshot(
        val atMs: Long,
        val packageName: String,
        val dump: String,
    )

    data class NotificationSnapshot(
        val atMs: Long,
        val packageName: String,
        val text: String,
    )

    private const val WINDOW_MS = 60_000L

    /** 无障碍抓到一帧可读的树：入环形缓冲，并转发给 Dart。 */
    fun onTreeCaptured(packageName: String, dump: String) {
        val now = System.currentTimeMillis()
        snapshots.add(TreeSnapshot(now, packageName, dump))
        while (snapshots.isNotEmpty() && now - snapshots[0].atMs > WINDOW_MS) {
            snapshots.removeAt(0)
        }
        Log.i(TAG, "treeCaptured package=$packageName lines=${dump.lineSequence().count()} buffer=${snapshots.size}")
        forward("treeCaptured", mapOf("package" to packageName, "dump" to dump))
    }

    /** 通知监听抓到一条支付通知：入环形缓冲，并转发给 Dart。 */
    fun onNotificationCaptured(packageName: String, text: String) {
        val now = System.currentTimeMillis()
        notifications.add(NotificationSnapshot(now, packageName, text))
        while (notifications.isNotEmpty() && now - notifications[0].atMs > WINDOW_MS) {
            notifications.removeAt(0)
        }
        Log.i(TAG, "notificationCaptured package=$packageName text=${text.take(40)}")
        forward("notificationCaptured", mapOf("package" to packageName, "text" to text))
    }

    /** 取最近一帧 [packageName] 的树快照（截图留证用）；没有返回 null。 */
    fun recentSnapshot(packageName: String): TreeSnapshot? =
        snapshots.lastOrNull { it.packageName == packageName }

    /** 取最近一帧任意白名单包的树快照（截图兜底留证用）；没有返回 null。 */
    fun lastSnapshot(): TreeSnapshot? {
        val snapshot = snapshots.lastOrNull()
        Log.i(TAG, "lastSnapshot -> ${snapshot?.packageName ?: "null"} buffer=${snapshots.size}")
        return snapshot
    }

    /** 截图兜底的一次性现读：从无障碍服务取「当前前台应用 → 树」。 */
    fun requestCurrentTree(): Pair<String, String>? =
        accessibilityService?.dumpCurrentTree()

    /** 取最近一条 [packageName] 的通知文本（截图留证学通知规则用）；没有返回 null。 */
    fun lastNotification(packageName: String): NotificationSnapshot? =
        notifications.lastOrNull { it.packageName == packageName }

    private fun forward(method: String, args: Map<String, Any?>) {
        val ch = channel ?: return
        if (!dartReady) return
        ch.invokeMethod(method, args)
    }

    private const val TAG = "BeanCapture"
}
