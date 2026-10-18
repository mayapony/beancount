package com.jindou.bean_count

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * 自更新安装桥：Dart 侧只负责下载与文案，系统权限、APK 解析、
 * 签名/版本预检与安装 Intent 都放在这里。
 */
class UpdateInstaller(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.jindou.bean_count/update"
        private const val MIME_APK = "application/vnd.android.package-archive"
        private const val UPDATE_DIR = "update"
        private const val PROVIDER_SUFFIX = ".update.fileprovider"
    }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canInstall" -> result.success(canInstall())
            "openInstallSettings" -> {
                openInstallSettings()
                result.success(null)
            }
            "preflight" -> preflight(
                call.argument<String>("path"),
                call.argument<String>("expectedVersion"),
                result,
            )
            "install" -> install(call.argument<String>("path"), result)
            else -> result.notImplemented()
        }
    }

    private fun canInstall(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return activity.packageManager.canRequestPackageInstalls()
        }
        return true
    }

    private fun openInstallSettings() {
        val packageUri = Uri.parse("package:${activity.packageName}")
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, packageUri)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
        }
        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri),
            )
        }
    }

    private fun preflight(
        path: String?,
        expectedVersion: String?,
        result: MethodChannel.Result,
    ) {
        val file = safeFile(path)
        if (file == null || !file.exists()) {
            result.success(preflightMap(false, "parse", null, null, null))
            return
        }

        val flags = signingFlags()
        val archive = try {
            activity.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        } catch (_: Exception) {
            null
        }
        if (archive == null) {
            result.success(preflightMap(false, "parse", null, null, null))
            return
        }

        val current = try {
            activity.packageManager.getPackageInfo(activity.packageName, flags)
        } catch (_: Exception) {
            null
        }
        val apkCode = versionCode(archive)
        val currentCode = current?.let { versionCode(it) }
        val apkName = archive.versionName
        val map = preflightMap(true, "ok", apkCode, currentCode, apkName)

        when {
            expectedVersion != null && apkName != expectedVersion -> {
                map["ok"] = false
                map["reason"] = "versionName"
            }
            currentCode != null && apkCode < currentCode -> {
                map["ok"] = false
                map["reason"] = "downgrade"
            }
            current != null && !sameSigner(archive, current) -> {
                map["ok"] = false
                map["reason"] = "signature"
            }
            !hasInstaller() -> {
                map["ok"] = false
                map["reason"] = "noInstaller"
            }
        }
        result.success(map)
    }

    private fun install(path: String?, result: MethodChannel.Result) {
        val file = safeFile(path)
        if (file == null || !file.exists()) {
            result.error("invalid_path", "安装包路径无效", null)
            return
        }
        if (!canInstall()) {
            result.error("permission", "需要允许安装未知应用", null)
            return
        }

        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}$PROVIDER_SUFFIX",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, MIME_APK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(activity.packageManager) == null) {
            result.error("no_installer", "系统没有可用的安装器", null)
            return
        }
        try {
            activity.startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("no_installer", "系统没有可用的安装器", null)
        } catch (_: Exception) {
            result.error("install_failed", "无法拉起系统安装器", null)
        }
    }

    /** 只允许 cache/update 下的文件，防止把任意路径交给 FileProvider。 */
    private fun safeFile(path: String?): File? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path).canonicalFile
            val dir = File(activity.cacheDir, UPDATE_DIR).canonicalFile
            if (file.path == dir.path ||
                file.path.startsWith(dir.path + File.separator)
            ) {
                file
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun hasInstaller(): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).setType(MIME_APK)
        return intent.resolveActivity(activity.packageManager) != null
    }

    private fun preflightMap(
        ok: Boolean,
        reason: String,
        apkCode: Long?,
        currentCode: Long?,
        apkName: String?,
    ): MutableMap<String, Any?> = mutableMapOf(
        "ok" to ok,
        "reason" to reason,
        "apkVersionCode" to apkCode,
        "currentVersionCode" to currentCode,
        "apkVersionName" to apkName,
    )

    @Suppress("DEPRECATION")
    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }

    @Suppress("DEPRECATION")
    private fun signatures(info: PackageInfo): List<String> {
        val sigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            info.signatures ?: emptyArray()
        }
        return sigs.map { sha256(it.toByteArray()) }.sorted()
    }

    private fun sameSigner(archive: PackageInfo, current: PackageInfo): Boolean {
        val left = signatures(archive)
        val right = signatures(current)
        return left.isNotEmpty() && left == right
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it.toInt() and 0xFF) }
}
