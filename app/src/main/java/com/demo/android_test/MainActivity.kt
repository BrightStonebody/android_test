package com.demo.android_test

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val a = com.demo.library_demo.R.string.library_demo
        val b = com.demo.library_demo2.R.string.library_demo2
        val c = R.string.app_name
        Log.i("chenlei_test", "onCreate: ${a + b + c}")

    }
    val library_demo = 0x7f0e002b
    val library_demo2 = 0x7f0e002c

}