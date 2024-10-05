package com.ss.android.ecommerce.spi

import androidx.annotation.Keep
import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.Dependencies
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.gson.reflect.TypeToken
import com.squareup.kotlinpoet.ClassName
import com.squareup.kotlinpoet.CodeBlock
import com.squareup.kotlinpoet.FileSpec
import com.squareup.kotlinpoet.FunSpec
import com.squareup.kotlinpoet.KModifier
import com.squareup.kotlinpoet.ParameterizedTypeName.Companion.parameterizedBy
import com.squareup.kotlinpoet.PropertySpec
import com.squareup.kotlinpoet.TypeSpec
import com.squareup.kotlinpoet.TypeVariableName
import com.squareup.kotlinpoet.asClassName
import com.squareup.kotlinpoet.ksp.writeTo
import com.ss.android.ecommerce.servicemanager.annotation.EcomSpiCollector
import com.ss.android.ecommerce.spi.ImplGenerateProcessor.Companion.TAG
import com.ss.android.ecommerce.spi.ImplGenerateProcessor.Companion.gson
import java.io.File
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes

class InitCollectionGenerateProcessor(
    val codeGenerator: CodeGenerator,
    val logger: KSPLogger,
    val environmentOptions: Map<String, String>,
) : SymbolProcessor {


    companion object {
        const val SERVICE_TYPE_MAP = "serviceTypeMap"
        const val INITIALIZE_CLASS_NAME = "EcomServiceInitialize"
        const val INITIALIZE_INTERFACE =
            "com.ss.android.ecommerce.servicemanager.IEcomServiceInitialize"
    }

    private var hasProcess = false


    override fun process(resolver: Resolver): List<KSAnnotated> {
        if (hasProcess) {
            return emptyList()
        }

        val ecomSpiCollectorClass =
            resolver.getSymbolsWithAnnotation(EcomSpiCollector::class.java.canonicalName)
        if (!ecomSpiCollectorClass.iterator().hasNext()) {
            return emptyList()
        }

        logger.warn("$TAG, InitCollectionGenerateProcessor start")

        val moduleName = environmentOptions["module_name"]

        val projectBuildPathList = environmentOptions["ecomProject.implBuildPaths"]?.split(";")
        if (projectBuildPathList.isNullOrEmpty()) {
            throw Exception("$TAG projectBuildPathList is empty")
        }

        var serviceNodeList = collectAllServiceInfo(projectBuildPathList)
        serviceNodeList = serviceNodeList.filter { !it.isHost }
        logger.warn("$TAG $moduleName ${serviceNodeList.size}")
        generateServiceInitialize(serviceNodeList)

        hasProcess = true

        return emptyList()
    }

    private fun collectAllServiceInfo(
        buildPathList: List<String>
    ): List<ServiceNode> {
        val serviceJsonPathList = mutableListOf<String>()
        buildPathList.forEach { subBuildPathStr ->
            val buildPath = Paths.get(subBuildPathStr)
            if (!buildPath.toFile().exists()) {
                return@forEach
            }
            Files.walkFileTree(
                buildPath,
                object : SimpleFileVisitor<Path>() {
                    override fun visitFile(
                        file: Path?,
                        attrs: BasicFileAttributes?
                    ): FileVisitResult {
                        val filePathStr = file.toString()
                        if (filePathStr
                                .endsWith(ImplGenerateProcessor.GENERATE_MODULE_FILE_NAME + ".json")
                        ) {
                            serviceJsonPathList.add(filePathStr)
                        }
                        return FileVisitResult.CONTINUE
                    }
                },
            )
        }

        val serviceNodeMap = HashMap<String, ServiceNode>()

        serviceJsonPathList.forEach { jsonFilePath ->
            val content = File(jsonFilePath).readText()
            val serviceNode = gson.fromJson<List<ServiceNode>>(
                content,
                object : TypeToken<ArrayList<ServiceNode>>() {}.type,
            )

            serviceNode.forEach { node ->
                val storeNode = serviceNodeMap[node.serviceName]
                if (storeNode != null) {
                    if (node.serviceImpl.isNotEmpty()) {
                        storeNode.serviceImpl = node.serviceImpl
                    }
                    if (node.serviceDefaultImpl.isNotEmpty()) {
                        storeNode.serviceDefaultImpl = node.serviceDefaultImpl
                    }
                } else {
                    serviceNodeMap[node.serviceName] = node
                }
            }
        }

        return serviceNodeMap.values.toList()
    }

    private fun generateServiceInitialize(serviceNodeList: List<ServiceNode>) {
        val fileSpec = FileSpec
            .builder(ImplGenerateProcessor.PACKAGE_NAME, INITIALIZE_CLASS_NAME)
            .addType(
                TypeSpec
                    .classBuilder(INITIALIZE_CLASS_NAME)
                    .addAnnotation(Keep::class)
                    .addSuperinterface(ClassName.bestGuess(INITIALIZE_INTERFACE))
                    .addModifiers(KModifier.FINAL)
                    .buildInitializeClassContent(serviceNodeList)
                    .build(),
            )
            .build()
        fileSpec.writeTo(codeGenerator, Dependencies.ALL_FILES)
    }

    private fun TypeSpec.Builder.buildInitializeClassContent(serviceNodeList: List<ServiceNode>): TypeSpec.Builder {
        /**
         * private val serviceTypeMap: HashMap<Class<*>, Int> = hashMapOf()
         */
        addProperty(
            PropertySpec.builder(
                SERVICE_TYPE_MAP,
                HashMap::class.asClassName().parameterizedBy(
                    Class::class.asClassName()
                        .parameterizedBy(TypeVariableName("*")),
                    Int::class.asClassName(),
                ),
            )
                .addModifiers(KModifier.PRIVATE)
                .initializer("hashMapOf()")
                .build(),
        )

        serviceNodeList.forEachIndexed { index, node ->
            /**
             * var mXxxxxService: IXxxxService? = null
             */
//            .addStatement("var ${getServiceFieldName(node)}: ${node.serviceName}? = null")
            addProperty(
                PropertySpec.builder(
                    getServiceFieldName(node),
                    ClassName.bestGuess(node.serviceName).copy(nullable = true),
                )
                    .addModifiers(KModifier.PRIVATE)
                    .mutable()
                    .initializer("null")
                    .build(),
            )
        }

        /**
         * init {
         *  serviceTypeMap[XxxService::class.java] = 0
         * }
         */
        addInitializerBlock(
            CodeBlock.builder()
                .let { builder ->
                    serviceNodeList.forEachIndexed { index, node ->
                        builder.addStatement(
                            "$SERVICE_TYPE_MAP[%T::class.java] = %L",
                            ClassName.bestGuess(node.serviceName), index,
                        )
                    }
                    builder
                }
                .build(),
        )

        /**
         * override fun getService(clazz: IECommerceHostService)
         */
        addFunction(
            FunSpec
                .builder("getService")
                .addModifiers(KModifier.OVERRIDE)
                .addTypeVariable(
                    TypeVariableName("T"),
                )
                .addParameter(
                    "service",
                    Class::class.asClassName().parameterizedBy(TypeVariableName("*")),
                )
                .addCode(
                    CodeBlock.builder()
                        .addStatement("val iService = $SERVICE_TYPE_MAP[service]")
                        .beginControlFlow("when (iService)")
                        .apply {
                            serviceNodeList.forEachIndexed { index, node ->
                                buildWhenCaseContent(index, node)
                            }
                        }
                        .endControlFlow()
                        .addStatement("return null")
//                        .addStatement("throw Exception(\"service \$service not found\")")
                        .build(),
                )
                .returns(TypeVariableName("T").copy(nullable = true))
                .build(),
        )

        return this
    }

    private fun CodeBlock.Builder.buildWhenCaseContent(index: Int, node: ServiceNode) {
        val fieldName = getServiceFieldName(node)
        beginControlFlow("%L ->", index).apply {
            beginControlFlow("if (%N == null)", fieldName).apply {
                beginControlFlow("synchronized(iService)").apply {
                    beginControlFlow("if (%N == null)", fieldName).apply {
                        addStatement(
                            "val service = %T()",
                            if (node.serviceImpl.isNotEmpty())
                                ClassName.bestGuess(node.serviceImpl)
                            else if (node.serviceDefaultImpl.isNotEmpty())
                                ClassName.bestGuess(node.serviceDefaultImpl)
                            else
                                throw Exception("service ${node.serviceName} has no serviceImpl and serviceDefaultImpl"),
                        )
                        addStatement("$fieldName = service")
                    }
                    endControlFlow()
                }
                addStatement(
                    "return %N as T",
                    fieldName,
                )
                endControlFlow()
            }
            endControlFlow()
        }
        endControlFlow()
    }

    private fun getServiceFieldName(node: ServiceNode): String {
        return "m${node.serviceName.substringAfterLast(".")}"
    }
}
