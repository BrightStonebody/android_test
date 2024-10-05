package com.ss.android.ecommerce.spi

import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.Dependencies
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSAnnotation
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.KSType
import com.google.gson.Gson
import com.squareup.kotlinpoet.ksp.toClassName
import com.ss.android.ecommerce.servicemanager.EcomService
import com.ss.android.ecommerce.servicemanager.HostEcomService

class ImplGenerateProcessor(
    val codeGenerator: CodeGenerator,
    val logger: KSPLogger,
    val environmentOptions: Map<String, String>,
) : SymbolProcessor {

    companion object {
        val gson = Gson()

        const val TAG = "ecommerce_saas_spi"
        const val PACKAGE_NAME = "com.ss.android.ecommerce.spi"
        const val ARGUMENT_MODULE_NAME = "module_name"
        const val GENERATE_MODULE_FILE_NAME = "service_collection"
        const val SERVICE_MANAGER_ANNOTATION_NAME_SHORT = "EcommerceService"
        const val SERVICE_MANAGER_ANNOTATION =
            "com.ss.android.ecommerce.spi.annotation.$SERVICE_MANAGER_ANNOTATION_NAME_SHORT"
    }

    private var hasProcess = false

    override fun process(resolver: Resolver): List<KSAnnotated> {
        if (hasProcess) {
            return emptyList()
        }
//        throw Exception("$TAG start")
        if (environmentOptions[ARGUMENT_MODULE_NAME].isNullOrBlank()) {
            throw Exception("$TAG module name must be set")
        }
        val module = environmentOptions[ARGUMENT_MODULE_NAME]
        logger.warn("$TAG, $module")

        val fileName = "${module}_$GENERATE_MODULE_FILE_NAME"
        logger.warn("$TAG module $module start")
        val nodeMap = HashMap<String, ServiceNode>()

        resolver.getSymbolsWithAnnotation(HostEcomService::class.qualifiedName ?: "").forEach { kClass ->
            val annotation =
                kClass.annotations.find { it.shortName.asString() == HostEcomService::class.simpleName }
                    ?: throw Exception("$TAG class not found annotation")
            logger.warn(
                "$TAG module $module, " +
                    "found class ${(kClass as? KSClassDeclaration)?.asType(emptyList())}",
            )

            parseAnnotation(annotation, kClass, true, nodeMap)
        }
        resolver.getSymbolsWithAnnotation(EcomService::class.qualifiedName ?: "").forEach { kClass ->
            val annotation =
                kClass.annotations.find { it.shortName.asString() == EcomService::class.simpleName }
                    ?: throw Exception("$TAG class not found annotation")
            logger.warn(
                "$TAG module $module, " +
                    "found class ${(kClass as? KSClassDeclaration)?.asType(emptyList())}",
            )

            parseAnnotation(annotation, kClass, false, nodeMap)
        }


        nodeMap.forEach { entry ->
            if (entry.value.serviceImpl.isBlank()
                && entry.value.serviceDefaultImpl.isBlank()) {
                throw Exception("serviceImpl and serviceDefaultImpl must not null")
            }
        }


        val outputStream = codeGenerator.createNewFile(
            Dependencies.ALL_FILES,
            PACKAGE_NAME,
            fileName,
            extensionName = "json",
        )
        val jsonStr = gson.toJson(nodeMap.values)
        outputStream.write(jsonStr.toByteArray())
        outputStream.flush()
        outputStream.close()
        hasProcess = true

        return emptyList()
    }

    private fun parseAnnotation(
        annotation: KSAnnotation,
        kClass: KSAnnotated,
        isHost: Boolean,
        nodeMap: HashMap<String, ServiceNode>
    ) {
        data class SpiAnnotation(
            var service: KSType? = null,
            var isDefaultImpl: Boolean = false,
            var isHost: Boolean = false,
        )

        val spiAnnotation = SpiAnnotation()
        annotation.arguments.forEach { value ->
            when (value.name?.getShortName()) {
                "isDefaultImpl" -> {
                    spiAnnotation.isDefaultImpl = value.value as Boolean
                }
                "service" -> {
                    spiAnnotation.service = if (isHost) {
                        value.value as KSType
                    } else {
                        (value.value as List<KSType>).first()
                    }
                }
                "isHost" -> {
                    spiAnnotation.isHost = isHost
                }
            }
        }

        val serviceName = spiAnnotation.service?.toClassName()?.canonicalName
        if (serviceName.isNullOrBlank()) {
            throw Exception("${HostEcomService::class.simpleName} must has a param [service]")
        }
        val implName =
            (kClass as? KSClassDeclaration)?.asType(emptyList())?.toClassName()?.canonicalName
        if (implName.isNullOrBlank()) {
            throw Exception("${HostEcomService::class.simpleName} get implName fail")
        }

        val node = nodeMap[serviceName] ?: ServiceNode()
        node.serviceName = serviceName
        node.isHost = isHost
        if (spiAnnotation.isDefaultImpl) {
            node.serviceDefaultImpl = implName
        } else {
            node.serviceImpl = implName
        }
        nodeMap[serviceName] = node
    }
}

/**
 */
data class ServiceNode(
    var serviceName: String = "",
    var serviceImpl: String = "",
    var serviceDefaultImpl: String = "",
    var isHost: Boolean = false,
)