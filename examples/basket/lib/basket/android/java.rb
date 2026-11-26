# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"
require_relative "vm"

module Basket
  module Android
    # The part of Java that Basket calls, in Ruby alone: JNI, the
    # interface Android's runtime gives native code, reached through
    # Fiddle. Any Ruby on Android can do what this file does.
    #
    # Each call spells out its JNI signature, as Android's reference
    # lists the method, and the signature says how Ruby's values become
    # Java's: a Ruby String is a Java String, +true+ a boolean, and an
    # Instance or a Klass the Java object it holds.
    #
    #   edit = Java::Klass["android.widget.EditText"].new("(Landroid/content/Context;)V", activity)
    #   edit.call("setHint", "(Ljava/lang/CharSequence;)V", "Add an item")
    #
    # Every Java object Ruby holds is a global reference that Ruby's
    # collector deletes, so a program that runs for days does not fill the
    # table of local references that Java empties only when a native
    # method returns.
    module Java
      # Raised when Java throws, with the exception's text.
      class Error < StandardError; end

      # Fiddle's type for a pointer.
      P = Fiddle::TYPE_VOIDP
      # Fiddle's type for an int.
      I = Fiddle::TYPE_INT
      # Fiddle's type for no value.
      V = Fiddle::TYPE_VOID
      # Fiddle's type for a byte, which a Java boolean is.
      U = Fiddle::TYPE_UCHAR
      # What frees memory Fiddle allocated.
      FREE = Fiddle::RUBY_FREE
      # How many bytes a pointer takes.
      WORD = Fiddle::SIZEOF_VOIDP

      # The JNI version Basket asks for: Java 6's, which Android has.
      VERSION_1_6 = 0x00010006

      # Where each function of JNIEnv's table is, from jni.h's
      # JNINativeInterface, which Java's and Android's share.
      TABLE = {
        find_class: 6,
        exception_occurred: 15,
        exception_clear: 17,
        new_global_ref: 21,
        delete_global_ref: 22,
        delete_local_ref: 23,
        is_same_object: 24,
        new_local_ref: 25,
        new_object: 30,
        get_object_class: 31,
        is_instance_of: 32,
        get_method_id: 33,
        get_field_id: 94,
        get_object_field: 95,
        get_static_method_id: 113,
        get_static_field_id: 144,
        new_string: 163,
        get_string_length: 164,
        get_array_length: 171,
        new_object_array: 172,
        get_object_array_element: 173,
        set_object_array_element: 174,
        new_byte_array: 176,
        set_byte_array_region: 208,
        register_natives: 215,
        get_string_region: 220,
        exception_check: 228,
      }.freeze

      # What each kind of Java type needs, by its letter in a signature
      # (arrays are objects, "L"): the Fiddle type of its value, how a
      # jvalue packs it, and where JNIEnv's table has Call<Type>MethodA,
      # CallStatic<Type>MethodA, and GetStatic<Type>Field.
      TYPES = {
        "Z" => [U, "C", 39, 119, 146],
        "I" => [I, "l<", 51, 131, 150],
        "J" => [Fiddle::TYPE_LONG_LONG, "q<", 54, 134, 151],
        "F" => [Fiddle::TYPE_FLOAT, "e", 57, 137, 152],
        "V" => [V, nil, 63, 143, nil],
        "L" => [P, "Q<", 36, 116, 145],
      }.freeze

      # The descriptor of java.lang.String, which Ruby's String stands for.
      STRING = "Ljava/lang/String;"

      @functions = {}

      class << self
        # This thread's JNIEnv, attaching the thread to Java first when
        # Java has not seen it, as a Ruby thread of the program's own.
        def env
          Thread.current.thread_variable_get(:basket_jni_env) || begin
            slot = Fiddle::Pointer.malloc(WORD, FREE)
            status = through(VM.pointer, 6, [P, P, I], I).call(VM.pointer, slot, VERSION_1_6)
            through(VM.pointer, 4, [P, P, P], I).call(VM.pointer, slot, nil) unless status.zero?
            Thread.current.thread_variable_set(:basket_jni_env, slot[0, WORD].unpack1("J"))
          end
        end

        # Calls the function of JNIEnv's table at +index+ (a key of TABLE
        # works too), whose Fiddle types after the JNIEnv are +arguments+,
        # and raises Error if Java threw.
        def call(index, arguments, returns, *values)
          raw(index, arguments, returns, *values).tap { check }
        end

        # Like call, but leaves a thrown exception for the caller.
        def raw(index, arguments, returns, *values)
          env = self.env
          index = TABLE.fetch(index) if index.is_a?(Symbol)
          function = (@functions[[index, arguments, returns]] ||= through(env, index, [P] + arguments, returns))
          function.call(env, *values)
        end

        # Raises an Error for the exception Java is throwing, if any,
        # after clearing it.
        def check
          return if raw(:exception_check, [], U).zero?

          throwable = raw(:exception_occurred, [], P).to_i
          raw(:exception_clear, [], V)
          object = raw(:find_class, [P], P, "java/lang/Object")
          to_string = raw(:get_method_id, [P, P, P], P, object, "toString", "()Ljava/lang/String;")
          raise Error, string(raw(TYPES.fetch("L")[2], [P, P, P], P, throwable, to_string, nil).to_i)
        end

        # The Java object +ref+, a local reference this deletes, as Ruby
        # holds it: a String for a Java String, nil for null, else an
        # Instance. +descriptor+ is its JNI type.
        def wrap(descriptor, ref)
          return nil if ref.zero?

          (descriptor == STRING) ? string(ref) : borrow(ref)
        ensure
          delete_local(ref) unless ref.zero?
        end

        # An Instance of the object +ref+, which stays the caller's.
        def borrow(ref)
          Instance.new(call(:new_global_ref, [P], P, ref).to_i)
        end

        # The text of the Java String +ref+.
        def string(ref)
          length = call(:get_string_length, [P], I, ref)
          buffer = Fiddle::Pointer.malloc([length * 2, 1].max, FREE)
          call(:get_string_region, [P, I, I, P], V, ref, 0, length, buffer)
          buffer[0, length * 2].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
        end

        # A Java String of +text+, a local reference.
        def new_string(text)
          units = text.encode(Encoding::UTF_16LE)
          call(:new_string, [P, I], P, units, units.bytesize / 2).to_i
        end

        # Deletes the local reference +ref+.
        def delete_local(ref)
          call(:delete_local_ref, [P], V, ref)
        end

        # Whether the references +one+ and +other+ are to the same object.
        def same?(one, other)
          call(:is_same_object, [P, P], U, one.to_i, other.to_i) != 0
        end

        # A Java array of the objects +items+, which are +klass+'s.
        def array(klass, items)
          array = call(:new_object_array, [I, P, P], P, items.size, klass.ref, 0).to_i
          items.each_with_index { |item, index| call(:set_object_array_element, [P, I, P], V, array, index, item.ref) }
          wrap("[", array)
        end

        # The Java byte array that holds the bytes of +data+.
        def bytes(data)
          array = call(:new_byte_array, [I], P, data.bytesize).to_i
          call(:set_byte_array_region, [P, I, I, P], V, array, 0, data.bytesize, data)
          wrap("[", array)
        end

        # The objects of the Java array +ref+.
        def elements(ref)
          Array.new(call(:get_array_length, [P], I, ref)) do |index|
            wrap("L", call(:get_object_array_element, [P, I], P, ref, index).to_i)
          end
        end

        # Calls the method +id+ of +target+, an object or a class, whose JNI
        # +signature+ says how +arguments+ become Java's and the result
        # Ruby's.
        def invoke(target, id, signature, arguments, static: false)
          packed(signature, arguments) do |values, returns|
            type = TYPES.fetch(kind(returns))
            finish(returns, call(type[static ? 3 : 2], [P, P, P], type[0], target, id, values))
          end
        end

        # A new object of the class +klass+, by the constructor +id+ of JNI
        # +signature+.
        def construct(klass, id, signature, arguments)
          packed(signature, arguments) do |values, _returns|
            wrap("L", call(:new_object, [P, P, P], P, klass, id, values).to_i)
          end
        end

        # The letter of +descriptor+'s kind in TYPES.
        def kind(descriptor)
          descriptor.start_with?("[") ? "L" : descriptor[0]
        end

        private def through(table_owner, index, arguments, returns)
          table = Fiddle::Pointer.new(Fiddle::Pointer.new(table_owner)[0, WORD].unpack1("J"))
          Fiddle::Function.new(table[index * WORD, WORD].unpack1("J"), arguments, returns)
        end

        # Yields the jvalues of +arguments+ for +signature+, and its
        # result's descriptor, then deletes the local references made for
        # the arguments.
        private def packed(signature, arguments)
          parameters, returns = signature.match(/\A\((.*)\)(.+)\z/).captures
          parameters = parameters.scan(/\[*(?:L[^;]+;|[A-Z])/)
          raise ArgumentError, "#{signature} takes #{parameters.size} arguments, not #{arguments.size}" unless parameters.size == arguments.size

          locals = []
          values = parameters.zip(arguments).map { |descriptor, value| jvalue(descriptor, value, locals) }.join
          yield(values.empty? ? nil : values, returns)
        ensure
          locals&.each { |ref| delete_local(ref) }
        end

        private def jvalue(descriptor, value, locals)
          kind = kind(descriptor)
          if kind == "L"
            ref = case value
            when nil then 0
            when ::String then new_string(value).tap { |made| locals << made }
            else value.ref
            end
            return [ref].pack("Q<")
          end

          number = (kind == "Z") ? (value ? 1 : 0) : value
          [number].pack(TYPES.fetch(kind)[1]).ljust(8, "\0")
        end

        private def finish(returns, result)
          case kind(returns)
          when "V" then nil
          when "Z" then result != 0
          when "L" then wrap(returns, result.to_i)
          else result
          end
        end
      end

      # A Java class, found by its Java name: its constructor, static
      # methods, and static int fields are Ruby methods of Klass.
      class Klass
        # The class named +name+, such as "android.widget.TextView".
        def self.[](name)
          (@all ||= {})[name] ||= new(name)
        end

        # The class's global reference, a jclass.
        attr_reader :ref

        # The name the class was found by.
        attr_reader :name

        # The class that +instance+, a java.lang.Class object, is, as a
        # loader other than the system's found it, named +name+.
        def self.of(name, instance)
          new(name, instance)
        end

        # Finds the class named +name+, unless +instance+ is it.
        def initialize(name, instance = nil)
          @name = name
          if instance
            @instance = instance
            @ref = instance.ref
          else
            local = Java.call(:find_class, [P], P, name.tr(".", "/")).to_i
            @ref = Java.call(:new_global_ref, [P], P, local).to_i
            Java.delete_local(local)
          end
        end

        # A new object of this class, by the constructor of JNI +signature+.
        def new(signature, *arguments)
          id = Java.call(:get_method_id, [P, P, P], P, ref, "<init>", signature).to_i
          Java.construct(ref, id, signature, arguments)
        end

        # Calls the static method +name+ of JNI +signature+.
        def call(name, signature, *arguments)
          id = Java.call(:get_static_method_id, [P, P, P], P, ref, name, signature).to_i
          Java.invoke(ref, id, signature, arguments, static: true)
        end

        # The value of the static int field +name+. Looking the field up
        # makes Java initialize the class, which its constants need.
        def int(name)
          id = Java.call(:get_static_field_id, [P, P, P], P, ref, name, "I").to_i
          Java.call(Java::TYPES.fetch("I")[4], [P, P], I, ref, id)
        end
      end

      # A Java object, held by a global reference that Ruby's collector
      # deletes. It calls Java's methods by name and signature.
      class Instance
        # What deletes the global reference +ref+, for Ruby's collector to
        # call.
        def self.release(ref)
          proc { Java.call(:delete_global_ref, [P], V, ref) }
        end

        # The global reference, a jobject.
        attr_reader :ref

        # Holds the global reference +ref+.
        def initialize(ref)
          @ref = ref
          ObjectSpace.define_finalizer(self, self.class.release(ref))
        end

        # Calls the method +name+ of JNI +signature+.
        def call(name, signature, *arguments)
          klass = Java.call(:get_object_class, [P], P, ref).to_i
          id = Java.call(:get_method_id, [P, P, P], P, klass, name, signature).to_i
          Java.delete_local(klass)
          Java.invoke(ref, id, signature, arguments)
        end

        # The object in the field +name+, whose JNI type is +descriptor+.
        def field(name, descriptor)
          klass = Java.call(:get_object_class, [P], P, ref).to_i
          id = Java.call(:get_field_id, [P, P, P], P, klass, name, descriptor).to_i
          Java.delete_local(klass)
          Java.wrap(descriptor, Java.call(:get_object_field, [P, P], P, ref, id).to_i)
        end

        # The object's text, from Java's toString.
        def to_s
          call("toString", "()Ljava/lang/String;")
        end

        # Whether this object is an instance of the class +klass+, a Klass.
        def instance_of_klass?(klass)
          Java.call(:is_instance_of, [P, P], U, ref, klass.ref) != 0
        end

        # Whether +other+ is the same Java object.
        def ==(other)
          other.respond_to?(:ref) && Java.same?(ref, other.ref)
        end
      end
    end
  end
end
