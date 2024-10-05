## plugin实现

```Kotlin
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
**        project.afterEvaluate {
            for (variant in android.libraryVariants) { // 遍历每一个变体，比如debug、release
                ... // hook aar打包
                ... // hook 源码编译
            }
        }**
   }
}
```

### hook aar打包

```Kotlin
                    variant.packageLibraryProvider.configure { // packageLibraryProvider是模块打包成aar的任务，在这个任务的configure阶段插入逻辑
                        val packageAar = it as BundleAar
                        packageAar.doLast { // 在打包aar的最后一步插入逻辑
                            transformBundle(
                                packageAar.archiveFile.get().asFile,
                                renameExtension
                            )
                        }
                    }
```

`variant.packageLibraryProvider`可以获取aar打包的task任务，添加doLast，可以获取到生成的aar文件。

进入`transformBundle`方法，修改字节码，并重写文件。

```Kotlin
    private fun transformBundle(bundleFile: File, renameExtension: RenameExtension) {
        println("chenlei_test transformBundle ${bundleFile.absolutePath}")

        if (bundleFile.extension == "jar") { // 如果是jar文件，直接进入下一步
            bundleFile.writeBytes(
                transformJar(
                    bundleFile.inputStream().readBytes(),
                    renameExtension
                )
            )
        } else if (bundleFile.extension == "aar") { // 如果是aar文件，解压后编译所有文件，处理jar文件并覆盖重写
            val modifyEntries = HashMap<String, ByteArray>()
            ZipFile(bundleFile).use { zipInput ->
                // 遍历修改aar中的每一个jar
                for (entry in zipInput.entries()) {
                    if (!entry.isDirectory && entry.name.endsWith(".jar")) { // 如果是jar文件，直接进入下一步
                        modifyEntries[entry.name] = // 暂存处理过的文件 entryName -> byte[]
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
                        val entry = entry.clone() as ZipEntry
                        entry.compressedSize = -1
                        outputStream.putNextEntry(entry)
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
```

这里会把aar当做zip文件来处理。 获取zip压缩包内的每一个单独文件（entry），重写字节码后重新输出zip。

这里用了kotlin的use拓展方法，自己内部会close文件流。

`outputStream.putNextEntry`和`outputStream.closeEntry()`分别代表一个entry的开头和结束符。

最后`bundleFile.writeBytes(byteArrayOutputStream.toByteArray())`覆盖重写了整个zip文件。



### hook 源码编译

```Kotlin
                    val bundleTask =
                        project.tasks.findByName("bundleLibRuntimeToJar" + variant.name.capitalize())
                    if (bundleTask is BundleLibraryClassesJar) { // 将源码库打包成jar的任务
                        bundleTask.doLast {
                            val jarFile = bundleTask.output.get().asFile
                            val newJarBytes = transformJar(jarFile.readBytes(), renameExtension)
                            jarFile.writeBytes(newJarBytes)
                        }
                    }
```

`"bundleLibRuntimeToJar" + variant.name.capitalize()`是子module打包成jar文件的任务。这里通过字符串获取这个task任务，并添加hook。

## asm修改字节码



### transformJar

```Kotlin
    private fun transformJar(inputBytes: ByteArray, renameExtension: RenameExtension): ByteArray {
        println("chenlei_test transformJar ")
        val inputStream = JarInputStream(inputBytes.inputStream())
        val bytesOutputStream = ByteArrayOutputStream()
        val outputStream = JarOutputStream(bytesOutputStream)
        while (true) {
            val jarEntry = inputStream.nextJarEntry
                ?: break
            println("chenlei_test transformJar ${jarEntry.name}")

            if (jarEntry.name.endsWith(".class")) { // 如果是class文件，通过asm处理
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
            } else { // 非class文件，直接copy
                val newJarEntry = JarEntry(jarEntry.name)
                outputStream.putNextEntry(newJarEntry)
                inputStream.copyTo(outputStream)
            }
            outputStream.closeEntry()
        }
        outputStream.close()
        inputStream.close()
        return bytesOutputStream.toByteArray()
    }
```

遍历jar文件中的所有文件，如果是class文件就调用asm进行字节码重写。

`ClassRemapper`是asm提供的api，需要提供一个ReMapper对象来实现rename规则。 `ClassRemapper`的实现原理在别的另一篇文章已经有提到。

注意：

```Kotlin
        outputStream.close()
        inputStream.close()
        return bytesOutputStream.toByteArray()
```

这里一定要close掉steam之后再获取byte[] 。因为outputStream中会有缓存，close时会输出缓存，如果先调用`bytesOutputStream.toByteArray()`，可能到只有缓存输出不到最后的`bytesOutputStream`中.



### 实现remapper定义规则

```Kotlin
class RenameMapper(
    packageMapping: Map<String, String>,
    classMapping: Map<String, String>
) : Remapper() {

    private val dotMapping = HashMap<String, String>() // com.demo.test
    private val slashMapping = HashMap<String, String>() // com/demo/test.class   

    init {
        for (entry in packageMapping) {
            var key = entry.key
            var value = entry.value
            key = if (key.endsWith("/")) key else "$key/" // package匹配必须以/结尾
            value = if (value.endsWith("/")) value else "$value/"
            slashMapping[key] = value
            key = key.replace("/", ".") // package匹配必须以.结尾
            value = value.replace("/", ".")
            key = if (key.endsWith(".")) key else "$key."
            value = if (value.endsWith(".")) value else "$value."
            dotMapping[key] = value
        }

        for (entry in classMapping) {
            var key = entry.key
            var value = entry.value
            slashMapping[key] = value
            dotMapping[key.replace("/", ".")] = value.replace("/", ".")
        }
    }

    override fun map(internalName: String): String {
        println("chenlei_test map $internalName")

        var newName = internalName
        val findPackageMapping = (dotMapping + slashMapping).entries.find {
            internalName.startsWith(it.key)
        }
        if (findPackageMapping != null) {
            newName = newName.replaceFirst(findPackageMapping.key, findPackageMapping.value)
        }
        println("chenlei_test map new $newName")
        return newName
    }

    override fun mapValue(value: Any?): Any {
        if (value !is String) {
            return super.mapValue(value)
        }

        println("chenlei_test mapValue $value")

        var value = value
        val startWithL = value.startsWith("L") // Lcom/demo/test   
        if (startWithL) {
            value = value.substring(1)
        }
        var newName = value
        val findPackageMapping = (dotMapping + slashMapping).entries.find {
            value.startsWith(it.key)
        }
        if (findPackageMapping != null) {
            newName = newName.replaceFirst(findPackageMapping.key, findPackageMapping.value)
        }

        if (startWithL) {
            newName = "L$newName"
        }
        println("chenlei_test mapValue new $newName")
        return newName
    }
}
```

这里只重写了两个方法。

`mapper`方法在asm遍历字节码的过程中，各种引用的字符串都会调用到这里。

`mapValue` 适用于常量，这里只需要对字符串的全类名引用做处理。



## 验证

使用插件：

```AWK
apply plugin: "rename_plugin"

rename_plugin {
    packageMapping = [
            "com/demo/library_demo": "com/demo/rename/demo"
    ]
}
```



源代码

```Kotlin
package com.demo.library_demo

class Test1 {
    val TEST_CONST = "com.demo.library_demo.Test23"

    companion object {
        const val TEST_CONST = "com.demo.library_demo.Test1"
        const val TEST_CONST2 = "com/demo/library_demo/Test1"
        const val TEST_CONST3 = "Lcom/demo/library_demo/Test1"
    }
}
```



从module的`build/intermediates/runtime_library_classes_jar/debug/classes.jar`

拿到编译后的jar文件，使用反编译查看代码。

可以看到，这个类的包名，常量都rename成功！

当然，前面说到了两个部分【hook aar打包】、【hook源码编译】。这里只能验证【hook源码编译】的部分。

