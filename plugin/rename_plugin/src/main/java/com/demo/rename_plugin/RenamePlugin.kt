package com.demo.rename_plugin

import com.android.build.gradle.AppExtension
import com.demo.rename_plugin.test.LifecycleLogTransform
import org.gradle.api.Plugin
import org.gradle.api.Project

/**
 * A simple 'hello world' plugin.
 */
class RenamePlugin : Plugin<Project> {
    override fun apply(project: Project) {
        val android = project.extensions.findByType(AppExtension::class.java)
            ?: return
        android.registerTransform(LifecycleLogTransform())
        val renameExtension = project.extensions.create("rename_plugin", RenameExtension::class.java)
        renameExtension.packageMapping.forEach { t, u ->
            println("key = $t")
            println("value = $u")
        }
    }
}

open class RenameExtension {
    var packageMapping = mutableMapOf<String, String>()
}
