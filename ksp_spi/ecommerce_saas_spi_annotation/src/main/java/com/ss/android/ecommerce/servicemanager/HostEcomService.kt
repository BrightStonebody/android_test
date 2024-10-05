package com.ss.android.ecommerce.servicemanager

import androidx.annotation.Keep
import kotlin.reflect.KClass

@Keep
@Target(AnnotationTarget.CLASS)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
annotation class HostEcomService(
    val service: KClass<out Any>,
    val isDefaultImpl: Boolean = false
)