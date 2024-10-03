package com.demo.rename_plugin

import com.android.build.gradle.LibraryExtension
import com.android.build.gradle.internal.tasks.BundleLibraryClassesJar
import com.android.build.gradle.tasks.BundleAar
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes
import org.objectweb.asm.commons.ClassRemapper
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.jar.JarEntry
import java.util.jar.JarInputStream
import java.util.jar.JarOutputStream
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * A simple 'hello world' plugin.
 */
class RenamePlugin : Plugin<Project> {
    override fun apply(project: Project) {
        // create extension 必须放在最前面，如果没有执行到的话，module调用rename_plugin的时候会报错
        val renameExtension =
            project.extensions.create("rename_plugin", RenameExtension::class.java)
        // LibraryExtension针对的是普通安卓模块
//        val android = project.extensions.findByType(LibraryExtension::class.java)
//         AppExtension针对的是app模块
//        val android = project.extensions.findByType(AppExtension::class.java)
        val android = project.extensions.findByName("android")

        project.afterEvaluate {
            if (android != null && android is LibraryExtension) {
                for (variant in android.libraryVariants) { // 遍历每一个变体，比如debug、release
                    variant.packageLibraryProvider.configure { // packageLibraryProvider是模块打包成aar的任务，在这个任务的configure阶段插入逻辑
                        val packageAar = it as BundleAar
                        packageAar.doLast { // 在打包aar的最后一步插入逻辑
                            transformBundle(
                                packageAar.archiveFile.get().asFile,
                                renameExtension
                            )
                        }
                    }

                    val bundleTask =
                        project.tasks.findByName("bundleLibRuntimeToJar" + variant.name.capitalize())
                    if (bundleTask is BundleLibraryClassesJar) { // 将源码库打包成jar的任务
                        bundleTask.doLast {
                            val jarFile = bundleTask.output.get().asFile
                            val newJarBytes = transformJar(jarFile.readBytes(), renameExtension)
                            jarFile.writeBytes(newJarBytes)
                        }
                    }
                }
            }
        }
    }

    private fun transformBundle(bundleFile: File, renameExtension: RenameExtension) {
        println("chenlei_test transformBundle ${bundleFile.absolutePath}")

        if (bundleFile.extension == "jar") {
            bundleFile.writeBytes(
                transformJar(
                    bundleFile.inputStream().readBytes(),
                    renameExtension
                )
            )
        } else if (bundleFile.extension == "aar") {
            val modifyEntries = HashMap<String, ByteArray>()
            ZipFile(bundleFile).use { zipInput ->
                // 遍历修改aar中的每一个jar
                for (entry in zipInput.entries()) {
                    if (!entry.isDirectory && entry.name.endsWith(".jar")) {
                        modifyEntries[entry.name] =
                            transformJar(
                                zipInput.getInputStream(entry).readBytes(),
                                renameExtension
                            )
                    }
                }
            }

            ZipFile(bundleFile).use { zipInput ->
                val byteArrayOutputStream = ByteArrayOutputStream()
                ZipOutputStream(byteArrayOutputStream).use { outputStream ->
                    for (entry in zipInput.entries()) {
                        outputStream.putNextEntry(JarEntry(entry.name))
                        val modifyEntry = modifyEntries[entry.name]
                        if (modifyEntry != null) {
                            outputStream.write(modifyEntry)
                        } else {
                            zipInput.getInputStream(entry).copyTo(outputStream)
                        }
                        outputStream.closeEntry()
                    }
                }
                bundleFile.writeBytes(byteArrayOutputStream.toByteArray())
            }

        }
    }

    private fun transformJar(inputBytes: ByteArray, renameExtension: RenameExtension): ByteArray {
        println("chenlei_test transformJar ")
        val inputStream = JarInputStream(inputBytes.inputStream())
        val bytesOutputStream = ByteArrayOutputStream()
        val outputStream = JarOutputStream(bytesOutputStream)
        while (true) {
            val jarEntry = inputStream.nextJarEntry
                ?: break
            println("chenlei_test transformJar ${jarEntry.name}")

            if (jarEntry.name.endsWith(".class")) {
                val renameMapper = RenameMapper(
                    renameExtension.packageMapping,
                    renameExtension.classMapping
                )
                val newJarEntry = JarEntry(renameMapper.map(jarEntry.name))
                outputStream.putNextEntry(newJarEntry)

                val classReader = ClassReader(inputStream.readBytes())
                val classWriter = ClassWriter(Opcodes.ASM8)
                classReader.accept(
                    ClassRemapper(classWriter, renameMapper), ClassReader.EXPAND_FRAMES
                )

                outputStream.write(classWriter.toByteArray())
            } else {
                val newJarEntry = JarEntry(jarEntry.name)
                outputStream.putNextEntry(newJarEntry)
                inputStream.copyTo(outputStream)
            }
            outputStream.closeEntry()
        }
        outputStream.close()
        inputStream.close()
        val byteArray = bytesOutputStream.toByteArray()
        return byteArray
    }
}

/**
 * 使用插件
 * rename_plugin {
 *     packageMapping = [
 *         "com.demo.test" to "com.demo.test2"
 *     ]
 * }
 */
open class RenameExtension {
    var packageMapping = mutableMapOf<String, String>()
    var classMapping = mutableMapOf<String, String>()
}
