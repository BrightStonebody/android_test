package com.demo.library_demo2

interface IPdpPreviewService {

    fun getCaches(productId: String): Any?

    /**
     * request preview data
     */
    fun doRequest(
        products: List<String>,
        trafficSourceList: List<Int>?,
        template: String? = null,
        sourcePageType: String? = null
    )
}