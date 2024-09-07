package com.demo.rename_plugin.test

import org.objectweb.asm.ClassVisitor
import org.objectweb.asm.MethodVisitor
import org.objectweb.asm.Opcodes


//

class LifecycleVisitor(cv: ClassVisitor) : ClassVisitor(Opcodes.ASM6, cv) {

    override fun visitMethod(
        access: Int,
        name: String?,
        desc: String?,
        signature: String?,
        exceptions: Array<out String>?
    ): MethodVisitor {
        val methodVisitor = super.visitMethod(access, name, desc, signature, exceptions)
        if (name == "onCreate" && desc == "(Landroid/os/Bundle;)V") {
            return LifecycleVisitorAdapter(methodVisitor, access, name, desc)
        }
        return methodVisitor
    }


}