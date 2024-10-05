package com.ss.android.ecommerce.servicemanager

interface IEcomHostServiceInitialize {
    
    fun <T>getService(service: Class<*>): T?
}