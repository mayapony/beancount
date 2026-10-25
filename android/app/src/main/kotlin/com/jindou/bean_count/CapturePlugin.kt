package com.jindou.bean_count

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter ↔ Android 的自动记账能力通道（主界面侧）。
 *
 * - setEnabled：写原生开关（开机恢复用）并启停后台捕获服务
 * - isAccessibilityEnabled / isNotificationListenerEnabled：读系统授权状态
 * - openAccessibilitySettings / openNotificationListenerSettings：深链到系统设置
 * - takeOpenAutoEntries：取走「点已记账通知要打开列表」的挂起标记
 */
class CapturePlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null

    fun attach(engine: FlutterEngine) {
        channel =
            MethodChannel(engine.dartExecutor.binaryMessenger, CaptureService.CHANNEL)
        channel?.setMethodCallHandler(this)
        handleIntent(activity.intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                CapturePrefs.setEnabled(activity, enabled)
                if (enabled) CaptureService.start(activity) else CaptureService.stop(activity)
                result.success(true)
            }

            "isAccessibilityEnabled" ->
                result.success(isServiceEnabled(AccessibilityCaptureService::class.java, true))

            "isNotificationListenerEnabled" ->
                result.success(isServiceEnabled(NotificationCaptureService::class.java, false))

            "openAccessibilitySettings" -> {
                activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(null)
            }

            "openNotificationListenerSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(null)
            }

            "takeOpenAutoEntries" ->
                result.success(CapturePrefs.takePendingOpenAutoEntries(activity))

            else -> result.notImplemented()
        }
    }

    /** 处理「已记账」通知：App 在前台时直接让 Shell 打开列表，否则挂起待取。 */
    fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(CaptureService.EXTRA_OPEN_AUTO_ENTRIES, false) == true) {
            intent.removeExtra(CaptureService.EXTRA_OPEN_AUTO_ENTRIES)
            CapturePrefs.setPendingOpenAutoEntries(activity, true)
            if (ScreenshotRuntime.isAppVisible) {
                CapturePrefs.takePendingOpenAutoEntries(activity)
                channel?.invokeMethod("openAutoEntries", null)
            }
        }
    }

    private fun isServiceEnabled(serviceClass: Class<*>, accessibility: Boolean): Boolean {
        val expected =
            ComponentName(activity, serviceClass).flattenToString()
        val key = if (accessibility) {
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        } else {
            Settings.Secure.ENABLED_NOTIFICATION_LISTENERS
        }
        val enabled = Settings.Secure.getString(activity.contentResolver, key).orEmpty()
        return enabled.split(':').contains(expected)
    }
}
