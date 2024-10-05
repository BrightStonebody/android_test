package com.ss.android.ecommerce.servicemanager

interface IEcomServiceInitialize {
    fun <T>getService(service: Class<*>): T?
}