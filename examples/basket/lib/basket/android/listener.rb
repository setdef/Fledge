# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"
require_relative "dex"
require_relative "java"

module Basket
  module Android
    # Java objects whose methods run Ruby: the listeners that Android's
    # views take, such as a View.OnClickListener.
    #
    # Android's runtime cannot define a class from native code, and its
    # SDK has no class that turns a call of an interface's method into a
    # call of native code. So Listener writes one class in memory, with
    # Dex: an InvocationHandler whose one method, +invoke+, is native. It
    # loads that class with InMemoryDexClassLoader, gives +invoke+ a
    # Fiddle closure with RegisterNatives, and makes each listener with
    # java.lang.reflect.Proxy, which makes a class of any interfaces at
    # run time and sends every call to the handler.
    #
    # A call from Java arrives on the thread that Java called from, which
    # for Android's views is the main thread, where Ruby runs.
    module Listener
      # The name of the class Ruby writes.
      HANDLER = "basket.Handler"
      # The JNI signature of InvocationHandler.invoke.
      INVOKE = "(Ljava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;"
      # The JNI signature of Proxy.newProxyInstance.
      NEW_PROXY = "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;"
      # How to read a boxed Java number or boolean as Ruby's, by class.
      UNBOXING = {
        "java.lang.Integer" => ["intValue", "()I"],
        "java.lang.Long" => ["longValue", "()J"],
        "java.lang.Boolean" => ["booleanValue", "()Z"],
      }.freeze

      @proxies = []

      class << self
        # A Java object of the interfaces named +interfaces+ whose methods
        # run the lambdas of +handlers+, by method name. A method with no
        # lambda does nothing, and answers false, zero, or null. Each lambda
        # takes the method's arguments, with a Java number or boolean as
        # Ruby's, and a boolean method's lambda answers true or false.
        def implement(interfaces, handlers)
          classes = Java.array(Java::Klass["java.lang.Class"], interfaces.map { |name| Java::Klass[name] })
          proxy = Java::Klass["java.lang.reflect.Proxy"].call("newProxyInstance", NEW_PROXY, loader, classes, handler)
          @proxies << [proxy, handlers.transform_keys(&:to_s)]
          proxy
        end

        # Runs the call Java made of +method+ on the proxy +proxy_ref+
        # with the Java array +arguments_ref+, and returns a local
        # reference to the result. An exception would unwind through
        # Java's frames, which Ruby must never do, so Ruby prints it, as it
        # prints one a program does not rescue, and the call answers null.
        def dispatch(proxy_ref, method_ref, arguments_ref)
          method = Java.borrow(method_ref)
          name = method.call("getName", "()Ljava/lang/String;")
          returns = method.call("getReturnType", "()Ljava/lang/Class;").call("getName", "()Ljava/lang/String;")
          arguments = arguments_ref.zero? ? [] : Java.elements(arguments_ref).map { |argument| unbox(argument) }
          proxy, handlers = @proxies.find { |each, _| Java.same?(each.ref, proxy_ref) }
          answer(returns, handlers&.key?(name) ? handlers.fetch(name).call(*arguments) : own(name, proxy, arguments))
        rescue Exception => e
          warn(e.full_message(highlight: false))
          0
        end

        # What the proxy itself answers for the methods every Java object
        # has.
        private def own(name, proxy, arguments)
          case name
          when "hashCode" then proxy.ref & 0x7fffffff
          when "equals" then proxy == arguments.first
          when "toString" then "a Ruby listener"
          end
        end

        private def unbox(argument)
          return argument unless argument.is_a?(Java::Instance)

          UNBOXING.each do |name, (getter, signature)|
            return argument.call(getter, signature) if argument.instance_of_klass?(Java::Klass[name])
          end
          argument
        end

        # A local reference to +value+ as the Java type +returns+: a boxed
        # boolean or int, a String, or null.
        private def answer(returns, value)
          case returns
          when "boolean" then local(Java::Klass["java.lang.Boolean"].call("valueOf", "(Z)Ljava/lang/Boolean;", value ? true : false))
          when "int" then local(Java::Klass["java.lang.Integer"].call("valueOf", "(I)Ljava/lang/Integer;", value.to_i))
          when "java.lang.String" then Java.new_string(value.to_s)
          else 0
          end
        end

        private def local(instance)
          Java.call(:new_local_ref, [Java::P], Java::P, instance.ref).to_i
        end

        # The InvocationHandler that every listener's proxy sends its calls
        # to, and the loader of the class Ruby wrote for it.
        private def handler
          @handler ||= begin
            klass = Java::Klass.of(HANDLER, loader.call("loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", HANDLER))
            register(klass)
            klass.new("()V")
          end
        end

        private def loader
          @loader ||= begin
            buffer = Java::Klass["java.nio.ByteBuffer"].call("wrap", "([B)Ljava/nio/ByteBuffer;", Java.bytes(Dex.handler_class(HANDLER)))
            parent = Java::Klass["java.lang.ClassLoader"].call("getSystemClassLoader", "()Ljava/lang/ClassLoader;")
            Java::Klass["dalvik.system.InMemoryDexClassLoader"].new("(Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V", buffer, parent)
          end
        end

        # Gives the +invoke+ of +klass+ its code, a Fiddle closure that
        # Ruby keeps alive.
        private def register(klass)
          @closure = Fiddle::Closure::BlockCaller.new(Java::P, [Java::P] * 5) do |_env, _this, proxy, method, arguments|
            dispatch(proxy.to_i, method.to_i, arguments.to_i)
          end
          @native = [Fiddle::Pointer["invoke"], Fiddle::Pointer[INVOKE]]
          methods = [@native[0].to_i, @native[1].to_i, @closure.to_i].pack("Q<3")
          Java.call(:register_natives, [Java::P, Java::P, Java::I], Java::I, klass.ref, methods, 1)
        end
      end
    end
  end
end
