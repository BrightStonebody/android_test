package com.demo.rename_plugin.test

import com.android.build.api.transform.Format
import com.android.build.api.transform.JarInput
import com.android.build.api.transform.QualifiedContent
import com.android.build.api.transform.Transform
import com.android.build.api.transform.TransformInvocation
import com.android.build.gradle.internal.pipeline.TransformManager
import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes
import java.io.File
import java.io.FileOutputStream
import java.lang.Exception
import java.util.jar.JarEntry
import java.util.jar.JarInputStream
import java.util.jar.JarOutputStream

class LifecycleLogTransform : Transform() {
    override fun getName(): String {
        return "LifecycleLogTransform"
    }

    override fun getInputTypes(): MutableSet<QualifiedContent.ContentType> {
        return mutableSetOf(
            QualifiedContent.DefaultContentType.CLASSES
        )
    }

    override fun getScopes(): MutableSet<in QualifiedContent.Scope> {
        return TransformManager.SCOPE_FULL_PROJECT
    }

    override fun isIncremental(): Boolean {
        return false
    }

    override fun transform(transformInvocation: TransformInvocation) {
        if (transformInvocation.isIncremental) {
            transformInvocation.outputProvider.deleteAll()
        }

        transformInvocation.inputs.forEach { input ->
            // 包含我们手写的 Class 类及 R.class、BuildConfig.class 等
            input.directoryInputs.forEach { directoryInput ->
                val destFile = transformInvocation.outputProvider.getContentLocation(
                    directoryInput.name,
                    directoryInput.contentTypes,
                    directoryInput.scopes,
                    Format.DIRECTORY
                )

                try {
                    scanDirectory(directoryInput.file, directoryInput.file, destFile)
                } catch (e: Exception) {
                    e.printStackTrace()
                    throw e
                }
//                FileUtils.copyDirectory(directoryInput.file, destFile)
            }

            // jar文件，如第三方依赖
            input.jarInputs.forEach { jarInput ->
                val destFile = transformInvocation.outputProvider.getContentLocation(
                    jarInput.name,
                    jarInput.contentTypes,
                    jarInput.scopes,
                    Format.JAR
                )
                try {
                    scanJar(jarInput, destFile)
                } catch (e: Exception) {
                    e.printStackTrace()
                    throw e
                }
//                FileUtils.copyFile(jarInput.file, destFile)
            }
        }
    }

    private fun scanDirectory(file: File, inputDirFile: File, destDirFile: File) {
        if (file.isDirectory) {
            file.listFiles()?.forEach {
                scanDirectory(it, inputDirFile, destDirFile)
            }
        } else {
            val destFile = File(
                file.absolutePath.replace(inputDirFile.absolutePath, destDirFile.absolutePath)
            )
            if (!destFile.parentFile.exists()) {
                destFile.parentFile.mkdirs()
            }

            val inputStream = file.inputStream()
            val outputStream = destFile.outputStream()
            if (file.path.endsWith(".class")) {
                outputStream.write(
                    visit(inputStream.readBytes())
                )
            } else {
                outputStream.write(inputStream.readBytes())
            }
            inputStream.close()
            outputStream.close()
        }
    }

    private fun scanJar(jarInput: JarInput, destFile: File) {
        val jarInputStream = JarInputStream(jarInput.file.inputStream())
        if (!destFile.parentFile.exists()) {
            destFile.parentFile.mkdirs()
        }
        val jarOutputStream = JarOutputStream(FileOutputStream(destFile))

        while (true) {
            val inputEntry = jarInputStream.nextJarEntry
                ?: break
            jarOutputStream.putNextEntry(
                JarEntry(inputEntry.name)
            )

            if (inputEntry.name.endsWith(".class")) {
                jarOutputStream.write(
                    visit(jarInputStream.readBytes())
                )
            } else {
                jarOutputStream.write(jarInputStream.readBytes())
            }
            jarOutputStream.closeEntry()
        }
        jarOutputStream.close()
        jarInputStream.close()
    }

    private fun visit(bytes: ByteArray): ByteArray {
        val classReader = ClassReader(bytes)
        val classWriter = ClassWriter(Opcodes.ASM8)
        classReader.accept(LifecycleVisitor(classWriter), ClassReader.EXPAND_FRAMES)
        return classWriter.toByteArray()
    }

}