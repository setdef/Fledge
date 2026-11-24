// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT

package org.setdef.fledge;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * A Java interface implemented in Ruby, for Fledge::JNI, the runtime's
 * bridge from Ruby to Android's classes
 * (doc/contributors/design/phone-widgets.md): a listener of a view, a
 * Runnable, a lifecycle's callbacks. Java makes the object with
 * java.lang.reflect.Proxy, as Chaquopy, pyjnius, and rubicon-java make a
 * Python object a Java interface's, and each call of one of its methods
 * reaches {@link #call}, whose code the bridge registers from Ruby, with
 * the number by which the bridge knows the Ruby object.
 */
public final class RubyProxy implements InvocationHandler {
    private final long handle;

    private RubyProxy(long handle) {
        this.handle = handle;
    }

    /**
     * An object of each of {@code interfaces} whose methods call the
     * Ruby object the bridge numbered {@code handle}.
     */
    public static Object of(long handle, Class<?>[] interfaces) {
        return Proxy.newProxyInstance(RubyProxy.class.getClassLoader(), interfaces, new RubyProxy(handle));
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] arguments) {
        return call(handle, proxy, method, arguments == null ? new Object[0] : arguments);
    }

    /**
     * Calls {@code method} of the Ruby object numbered {@code handle} with
     * {@code arguments}, and returns its result, boxed as the method's
     * type is. The bridge registers its code with RegisterNatives as it
     * loads, before it makes any proxy.
     */
    private static native Object call(long handle, Object proxy, Method method, Object[] arguments);
}
