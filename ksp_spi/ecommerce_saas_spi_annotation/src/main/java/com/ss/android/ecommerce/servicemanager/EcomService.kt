package com.ss.android.ecommerce.servicemanager

import androidx.annotation.Keep
import kotlin.reflect.KClass

@Keep
@Target(AnnotationTarget.CLASS)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
annotation class EcomService(
    val service: Array<KClass<out Any>>,
    val isDefaultImpl: Boolean = false,
    val singleton: Boolean = true
)