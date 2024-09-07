package com.demo.rename_plugin.test

import org.objectweb.asm.Label
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes
import org.objectweb.asm.commons.AdviceAdapter


class LifecycleVisitorAdapter(
    val methodVisitor: MethodVisitor,
    access: Int,
    name: String,
    descriptor: String
) : AdviceAdapter(Opcodes.ASM6, methodVisitor, access, name, descriptor) {

    override fun onMethodEnter() {
        super.onMethodEnter()
        val label0 = Label()
        methodVisitor.visitLabel(label0)
        methodVisitor.visitLineNumber(9, label0)
        methodVisitor.visitLdcInsn("chenlei_test")
        methodVisitor.visitLdcInsn("function start")
        methodVisitor.visitMethodInsn(
            INVOKESTATIC,
            "android/util/Log",
            "d",
            "(Ljava/lang/String;Ljava/lang/String;)I",
            false
        )
        methodVisitor.visitInsn(POP)
    }

    override fun onMethodExit(opcode: Int) {
        super.onMethodExit(opcode)
        val label2 = Label()
        methodVisitor.visitLabel(label2)
        methodVisitor.visitLineNumber(13, label2)
        methodVisitor.visitLdcInsn("chenlei_test")
        methodVisitor.visitLdcInsn("function end")
        methodVisitor.visitMethodInsn(
            INVOKESTATIC,
            "android/util/Log",
            "d",
            "(Ljava/lang/String;Ljava/lang/String;)I",
            false
        )
        methodVisitor.visitInsn(POP)

    }
}