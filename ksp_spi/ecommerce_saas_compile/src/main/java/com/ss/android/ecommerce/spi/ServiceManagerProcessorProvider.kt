package com.ss.android.ecommerce.spi

import com.google.auto.service.AutoService
import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.processing.SymbolProcessorEnvironment
import com.google.devtools.ksp.processing.SymbolProcessorProvider
import com.google.devtools.ksp.symbol.KSAnnotated


class ServiceManagerProcessor(
    val codeGenerator: CodeGenerator,
    val logger: KSPLogger,
    val environmentOptions: Map<String, String>,
) : SymbolProcessor {

    private val processors = listOf(
        ImplGenerateProcessor(codeGenerator, logger, environmentOptions),
        HostCollectionGenerateProcessor(codeGenerator, logger, environmentOptions),
        InitCollectionGenerateProcessor(codeGenerator, logger, environmentOptions)
    )

    override fun process(resolver: Resolver): List<KSAnnotated> {
        processors.map {
            it.process(resolver)
        }
        return emptyList()
    }
}


/**
 */
//@AutoService(SymbolProcessorProvider::class)
class ServiceManagerProcessorProvider : SymbolProcessorProvider {

    override fun create(
        environment: SymbolProcessorEnvironment
    ): SymbolProcessor {
        return ServiceManagerProcessor(
            environment.codeGenerator,
            environment.logger,
            environment.options
        )
    }
}