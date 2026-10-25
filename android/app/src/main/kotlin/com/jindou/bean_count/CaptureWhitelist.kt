package com.jindou.bean_count

/**
 * 无障碍 / 通知采集的白名单包。
 *
 * 先只放微信、支付宝两家；云闪付与银行 App 视需要再加（design Open Question）。
 */
object CaptureWhitelist {
    private val packages = setOf(
        "com.tencent.mm",
        "com.eg.android.AlipayGphone",
    )

    fun contains(packageName: String): Boolean = packages.contains(packageName)
}
