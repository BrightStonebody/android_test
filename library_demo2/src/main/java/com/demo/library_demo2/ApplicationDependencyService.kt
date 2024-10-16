package com.demo.library_demo2

import android.app.Activity
import android.content.Context
import com.demo.library_demo.IApplicationDependencyService
import com.ss.android.ecommerce.servicemanager.HostEcomService

@HostEcomService(service = IApplicationDependencyService::class)
class ApplicationDependencyService: IApplicationDependencyService {


    override fun getAppId(): Int {
        return R.string.library_demo2
    }

    override fun getAppName(): String {
        return ""
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