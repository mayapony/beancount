package com.jindou.bean_count

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 无障碍采集：白名单包（微信 / 支付宝等）在前台、页面变化时，把控件树 dump 成
 * 缩进的文本快照交给 [CaptureRuntime]。
 *
 * 只读、不写任何账本数据；金额解析、去重、入账都在 Dart 侧。白名单之外的包
 * 一律不读——这是对「读全屏」观感的最小化。
 */
class AccessibilityCaptureService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val packageName = event.packageName?.toString() ?: return
        if (!CaptureWhitelist.contains(packageName)) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) {
            return
        }
        // 页面稳定后再取一帧：内容变化事件很密集，只关心最终态。
        val root = rootInActiveWindow ?: return
        val dump = dumpTree(root)
        CaptureRuntime.onTreeCaptured(packageName, dump)
    }

    override fun onInterrupt() = Unit

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
}
