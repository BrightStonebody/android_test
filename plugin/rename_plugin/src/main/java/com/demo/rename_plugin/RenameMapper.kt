package com.demo.rename_plugin

import org.objectweb.asm.commons.Remapper

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