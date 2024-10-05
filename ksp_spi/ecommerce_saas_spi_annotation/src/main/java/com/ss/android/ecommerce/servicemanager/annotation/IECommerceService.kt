package com.ss.android.ecommerce.servicemanager.annotation


interface IECommerceService {

    // 服务初始化
    fun initService() {}
}

interface IECommerceBusinessService : IECommerceService


interface IECommerceHostService : IECommerceService