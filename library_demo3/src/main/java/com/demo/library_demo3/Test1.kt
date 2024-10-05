package com.demo.library_demo

class Test1 {
    val TEST_CONST = "com.demo.library_demo.Test23"

    companion object {
        const val TEST_CONST = "com.demo.library_demo.Test1"
        const val TEST_CONST2 = "com/demo/library_demo/Test1"
        const val TEST_CONST3 = "Lcom/demo/library_demo/Test1"
    }
}