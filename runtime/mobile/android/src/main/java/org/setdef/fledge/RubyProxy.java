// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT

package org.setdef.fledge;

import java.lang.reflect.Array;
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
    /** Whether the app's Ruby has ended, after which no call may reach it. */
    private static volatile boolean ended;

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

    /**
     * Ends the calls into Ruby. Once Ruby's program ends, Ruby tears
     * down its closures, and Android goes on: its main thread still
     * delivers the lifecycle callbacks and clicks of the views Ruby made,
     * which would call into code that is gone. From then on a proxy's
     * method does nothing and returns zero, false, or null, as an
     * object's methods do, so that the app's windows close or stay as
     * they are without a crash.
     */
    public static void rubyEnded() {
        ended = true;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] arguments) {
        if (ended) return afterRuby(proxy, method, arguments);
        return call(handle, proxy, method, arguments == null ? new Object[0] : arguments);
    }

    /**
     * Calls {@code method} of the Ruby object numbered {@code handle} with
     * {@code arguments}, and returns its result, boxed as the method's
     * type is. The bridge registers its code with RegisterNatives as it
     * loads, before it makes any proxy.
     */
    private static native Object call(long handle, Object proxy, Method method, Object[] arguments);

    private static Object afterRuby(Object proxy, Method method, Object[] arguments) {
        switch (method.getName()) {
            case "equals":
                if (arguments != null && arguments.length == 1) return proxy == arguments[0];
                break;
            case "hashCode":
                if (arguments == null) return System.identityHashCode(proxy);
                break;
            case "toString":
                if (arguments == null) return proxy.getClass().getName() + "@" + Integer.toHexString(System.identityHashCode(proxy));
                break;
            default:
        }
        Class<?> type = method.getReturnType();
        return type.isPrimitive() && type != void.class ? Array.get(Array.newInstance(type, 1), 0) : null;
    }
}
