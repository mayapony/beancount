package com.jindou.bean_count

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

/**
 * 无障碍采集：只读「已认识」包（微信 / 支付宝 + 截图学到的）的控件树，dump 成
 * 缩进的文本快照交给 [CaptureRuntime]。
 *
 * 只读、不写任何账本数据；金额解析、去重、入账都在 Dart 侧。不认识的前台应用
 * 不持续读——这是对「读全屏」观感的最小化；只有用户主动截图记一笔时，才经
 * [dumpCurrentTree] 一次性现读当前页（见截图兜底）。
 *
 * 截图后 MIUI 会弹「截长屏/发送/小爱识屏」工具栏，它是系统悬浮窗，会把活动窗口
 * 顶掉；所以 [findAppWindow] 先看活动窗口、再看全部窗口，只认「非系统 / 已认识」
 * 的应用窗口，避免把工具栏当页面。
 */
class AccessibilityCaptureService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var pending = false

    private val dumpRunnable = Runnable {
        if (!pending) return@Runnable
        pending = false
        val found = findAppWindow { CapturePrefs.isKnown(this, it) }
        if (found == null) {
            Log.i(TAG, "dump: no known window active=${rootInActiveWindow?.packageName ?: "null"}")
            return@Runnable
        }
        val (packageName, root) = found
        val dump = dumpTree(root)
        if (dump.lineSequence().count() <= 1) return@Runnable
        Log.i(
            TAG,
            "dumpTree package=$packageName lines=${dump.lineSequence().count()} " +
                "text=${dump.replace('\n', ' ').take(160)}",
        )
        CaptureRuntime.onTreeCaptured(packageName, dump)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        CaptureRuntime.accessibilityService = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return
        if (!CapturePrefs.isKnown(this, packageName)) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            return
        }
        // 页面稳定后再取一帧：内容变化事件很密集，只关心最终态。
        pending = true
        handler.removeCallbacks(dumpRunnable)
        handler.postDelayed(dumpRunnable, DUMP_DELAY_MS)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        CaptureRuntime.accessibilityService = null
        super.onDestroy()
    }

    /**
     * 截图兜底的一次性现读：返回「包名 → 缩进树文本」。当前只有系统悬浮窗
     * （截图工具栏 / 状态栏）时返回 null，让调用方稍后重试。
     */
    fun dumpCurrentTree(): Pair<String, String>? {
        val found = findAppWindow { true }
        if (found == null) {
            Log.i(TAG, "dumpCurrentTree: no app window active=${rootInActiveWindow?.packageName ?: "null"}")
            return null
        }
        val (packageName, root) = found
        return packageName to dumpTree(root)
    }

    /**
     * 找匹配的应用窗口：遍历全部窗口、只认 `TYPE_APPLICATION`（应用窗口），
     * 跳过系统悬浮窗（截图工具栏 / 状态栏 / 输入法）。不用包名查系统属性——
     * Android 11+ 包可见性会让 `getApplicationInfo` 抛异常，误把第三方当系统。
     */
    private fun findAppWindow(match: (String) -> Boolean): Pair<String, AccessibilityNodeInfo>? {
        val windowList = windows ?: return null
        for (window in windowList) {
            if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
            val root = window.root ?: continue
            val pkg = root.packageName?.toString() ?: continue
            if (match(pkg)) return pkg to root
        }
        return null
    }

    private fun dumpTree(root: AccessibilityNodeInfo): String {
        val builder = StringBuilder()
        dumpNode(root, builder, 0)
        return builder.toString()
    }

    private fun dumpNode(node: AccessibilityNodeInfo, builder: StringBuilder, depth: Int) {
        val indent = "  ".repeat(depth)
        val text = node.text?.toString()?.trim().orEmpty()
        val className = node.className?.toString().orEmpty()
        if (text.isNotEmpty()) {
            builder.append(indent).append(className).append('|').append(text).append('\n')
        } else if (className.isNotEmpty()) {
            builder.append(indent).append(className).append('\n')
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            dumpNode(child, builder, depth + 1)
            child.recycle()
        }
    }

    companion object {
        private const val TAG = "BeanCapture"
        private const val DUMP_DELAY_MS = 300L
    }
}
