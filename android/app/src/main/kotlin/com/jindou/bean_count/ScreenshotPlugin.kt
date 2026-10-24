package com.jindou.bean_count

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Flutter ↔ Android 的截图能力通道。
 *
 * - setEnabled：写原生开关（开机恢复用）并启停前台服务
 * - requestPermissions：申请相册读权限（33+ READ_MEDIA_IMAGES）与通知权限
 * - hasPermissions：给设置页显示状态
 * - takeSharedImagePath：取走通过系统分享面板发来的图片
 */
class ScreenshotPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pendingSharedImagePath: String? = null

    /** 上一次「取回失败截图」没取到图：让 Dart 侧能说一句原因，而不是静默。 */
    private var pendingSharedImageError = false

    fun attach(engine: FlutterEngine) {
        channel =
            MethodChannel(engine.dartExecutor.binaryMessenger, ScreenshotService.CHANNEL)
        channel?.setMethodCallHandler(this)
        handleIntent(activity.intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                ScreenshotPrefs.setEnabled(activity, enabled)
                if (enabled) ScreenshotService.start(activity) else ScreenshotService.stop(activity)
                result.success(true)
            }

            "requestPermissions" -> requestPermissions(result)

            "hasPermissions" -> result.success(
                mapOf(
                    "media" to hasMediaPermission(),
                    "notifications" to hasNotificationPermission(),
                ),
            )

            "takeSharedImagePath" -> {
                val path = pendingSharedImagePath
                pendingSharedImagePath = null
                result.success(path)
            }

            // 取回失败截图时如果读不到图，Dart 侧据此提示原因（取一次就清零）。
            "takeSharedImageError" -> {
                val failed = pendingSharedImageError
                pendingSharedImageError = false
                result.success(failed)
            }

            else -> result.notImplemented()
        }
    }

    /** 处理系统分享面板发来的图片：复制到 cache，交一次给 Dart。 */
    fun handleIntent(intent: Intent?) {
        // 点识别结果通知：App 已经在前台时，直接让 Shell 消费待确认队列
        if (intent?.getBooleanExtra(ScreenshotService.EXTRA_CONSUME_PENDING, false) == true) {
            intent.removeExtra(ScreenshotService.EXTRA_CONSUME_PENDING)
            if (ScreenshotRuntime.isAppVisible) {
                channel?.invokeMethod("pendingAvailable", null)
            }
        }
        // 点「读取截图失败」通知：后台那次读不到（pending/超时），现在多半已发布，
        // 重新读一次当作「分享进来的一张图」，复用同一条识别 → 预填链路。
        if (intent?.getBooleanExtra(ScreenshotService.EXTRA_RECOVER_SCREENSHOT, false) == true) {
            intent.removeExtra(ScreenshotService.EXTRA_RECOVER_SCREENSHOT)
            val uri = ScreenshotPrefs.takeLastFailedUri(activity)
            val copied = uri?.let { copyToCache(Uri.parse(it)) }
            pendingSharedImageError = uri != null && copied == null
            if (copied != null) {
                pendingSharedImagePath = copied
                if (ScreenshotRuntime.isAppVisible) {
                    channel?.invokeMethod("sharedImageAvailable", null)
                }
            }
        }
        if (intent?.action != Intent.ACTION_SEND) return
        val type = intent.type ?: return
        if (!type.startsWith("image/")) return
        @Suppress("DEPRECATION")
        val uri: Uri? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        intent.removeExtra(Intent.EXTRA_STREAM)
        if (uri == null) return
        pendingSharedImagePath = copyToCache(uri)
        if (ScreenshotRuntime.isAppVisible && pendingSharedImagePath != null) {
            channel?.invokeMethod("sharedImageAvailable", null)
        }
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            val file = File(
                activity.cacheDir,
                "shared_${System.currentTimeMillis()}.jpg",
            )
            activity.contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasMediaPermission()) {
            result.success(true)
            return
        }
        permissionResult?.success(false)
        permissionResult = result
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        ActivityCompat.requestPermissions(
            activity,
            permissions.toTypedArray(),
            REQUEST_CODE,
        )
    }

    /** 返回 true 表示这个回调是截图权限申请的。 */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val granted = hasMediaPermission() ||
            (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        permissionResult?.success(granted && hasMediaPermission())
        permissionResult = null
        return true
    }

    private fun hasMediaPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val REQUEST_CODE = 4201
    }
}
