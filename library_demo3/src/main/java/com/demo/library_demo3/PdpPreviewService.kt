package com.demo.library_demo3

import com.demo.library_demo2.IPdpPreviewService
import com.ss.android.ecommerce.servicemanager.EcomService

@EcomService(service = [IPdpPreviewService::class])
class PdpPreviewService : IPdpPreviewService {
    override fun getCaches(productId: String): Any? {
        return null
    }

    override fun doRequest(
        products: List<String>,
        trafficSourceList: List<Int>?,
        template: String?,
        sourcePageType: String?
    ) {

    }
}