package com.demo.library_demo

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.demo.library_demo.R

class TestActivity2: AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        this.getString(R.string.library_demo)
//        R.string.abc_action_bar_home_description
    }
}

//const val library_demo = 0x7f0e002b
//const val library_demo2 = 0x7f0e002c


class R2 private constructor() {
    /* loaded from: classes2.dex */
    object string {
        const val library_demo = 0x7f0e002b
        const val library_demo2 = 0x7f0e002c
    }
}