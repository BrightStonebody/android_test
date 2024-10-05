package com.demo.library_demo

import android.app.Activity
import android.content.Context
import com.ss.android.ecommerce.servicemanager.HostEcomService

interface IApplicationDependencyService {

    /**
     * 获取宿主Appid
     */
    fun getAppId(): Int


    /**
     * 获取宿主的AppName
     */

    fun getAppName(): String

    /**
     * 获取宿主的Application
     */

    fun getApplicationContext(): Context

    /**
     * 渠道
     */
    fun getChannel(): String

    /**
     * 是否为debug环境
     */
    fun isDebug(): Boolean

    /**
     * 返回app locale
     */
    fun getAppLocale(): String

    /**
     * 是否是coin app
     */
    fun isCoinApp(): Boolean {
        return false
    }

    /**
     * @return Boolean
     */
    fun isAppHot(): Boolean

    /**
     * @param context Context?
     * @param scene Int
     */
    fun syncABAndSettings(context: Context? = null, scene: Int = 0)

    /**
     * 获取主页Activity
     */
    val mainActivityClass: Class<out Activity?>?

    /**
     * 当前页面是否为主页
     */
    fun isMainPage(context: Context?): Boolean

    //
    fun isFirstInstallAndFirstLaunchLowCost(): Boolean

    //
    fun isFirstInstallAndFirstLaunch(): Boolean

    // 是否 Pad 设备
    fun isPad(): Boolean
}

/**
 * default
 */
@HostEcomService(service = IApplicationDependencyService::class, isDefaultImpl = true)
class DefaultApplicationDependencyService : IApplicationDependencyService {

    override fun getAppId(): Int {
        return 123456
    }

    override fun getAppName(): String {
        return "shop"
    }

    override fun getApplicationContext(): Context {
        throw Exception("AppContextDependencyService not inject in host application")
    }

    override fun getChannel(): String {
        return "debug"
    }

    override fun isDebug(): Boolean {
        return true
    }

    override fun getAppLocale(): String {
        return "en_us"
    }

    override fun isAppHot(): Boolean {
        return false
    }

    override val mainActivityClass: Class<out Activity?>?
        get() = null

    override fun isMainPage(context: Context?): Boolean {
        return false
    }

    override fun syncABAndSettings(context: Context?, scene: Int) {
    }

    override fun isFirstInstallAndFirstLaunchLowCost(): Boolean {
        return false
    }

    override fun isFirstInstallAndFirstLaunch(): Boolean {
        return false
    }

    override fun isPad(): Boolean {
        return false
    }
}