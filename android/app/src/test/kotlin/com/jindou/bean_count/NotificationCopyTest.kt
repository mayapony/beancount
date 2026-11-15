package com.jindou.bean_count

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 常驻通知文案的四态：这是「两个开关共用一条通知」这条要求里唯一用户直接看到
 * 的东西，放在 JVM 单测里比真机肉眼回归可靠。
 */
class NotificationCopyTest {

    @Test
    fun `两个通道都关闭时没有常驻通知`() {
        assertNull(CaptureHostService.ongoingCopy(capture = false, screenshot = false))
    }

    @Test
    fun `只开自动记账`() {
        val copy = CaptureHostService.ongoingCopy(capture = true, screenshot = false)!!
        assertEquals("金豆正在守护", copy.title)
        assertTrue(copy.text.contains("自动记账"))
        assertTrue(!copy.text.contains("截屏"))
    }

    @Test
    fun `只开截屏监听`() {
        val copy = CaptureHostService.ongoingCopy(capture = false, screenshot = true)!!
        assertEquals("金豆正在守护", copy.title)
        assertTrue(copy.text.contains("截屏"))
        assertTrue(!copy.text.contains("自动记账"))
    }

    @Test
    fun `两个通道都开启时同一条通知说明两者`() {
        val copy = CaptureHostService.ongoingCopy(capture = true, screenshot = true)!!
        assertTrue(copy.text.contains("自动记账"))
        assertTrue(copy.text.contains("截屏"))
    }
}
