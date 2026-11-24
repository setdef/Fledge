# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fiddle"

module Fledge
  # Ruby's way to Java, and through it to Android's views, on Android
  # (doc/contributors/design/phone-widgets.md). It is Fledge's bridge, not
  # a layer of widgets: an app makes Android's own objects and calls
  # their methods, as Android documents them, and implements their
  # listeners' interfaces in Ruby. It speaks JNI, the Java VM's own C
  # interface, through Fiddle.
  #
  # A class is JNI.import's, by its Java name; a method is called by its
  # Java name, with Ruby values, and the bridge picks the overload whose
  # parameters take them, as pyjnius and Chaquopy pick one:
  #
  #   TextView = Fledge::JNI.import("android.widget.TextView")
  #   label = TextView.new(activity)
  #   label.setText("Hello")
  #   Fledge::JNI.import("android.widget.LinearLayout").VERTICAL # => 1
  #
  # A Java string comes back as a Ruby String; every other object as a
  # JNI::Object, which keeps it from Java's collector until Ruby collects
  # it. JNI.implement makes a Java interface's object of a Ruby one.
  #
  # Android's views are the main thread's alone, so an app that draws its
  # screen runs its Ruby on that thread (kind: windowed in fledge.yml),
  # builds its views on FledgeRuby.activity, and hands the thread back to
  # Android with JNI.loop.
  module JNI
    # Raised when Java throws: the exception's class and message.
    class JavaError < StandardError
      # The Throwable, a JNI::Object.
      attr_reader :throwable

      def initialize(message, throwable)
        super(message)
        @throwable = throwable
      end
    end

    # Raised when no method or constructor of a class takes the arguments.
    class Error < StandardError; end

    P = Fiddle::TYPE_VOIDP
    I = Fiddle::TYPE_INT
    J = Fiddle::TYPE_LONG_LONG

    # The JNI version the bridge asks for: Java 6's, which Android's has.
    VERSION_1_6 = 0x00010006

    # Where each function JNIEnv's table holds is, from jni.h's struct
    # JNINativeInterface, which Java's and Android's share.
    TABLE = {
      FindClass: 6,
      FromReflectedMethod: 7,
      FromReflectedField: 8,
      IsAssignableFrom: 11,
      ExceptionOccurred: 15,
      ExceptionClear: 17,
      NewGlobalRef: 21,
      DeleteGlobalRef: 22,
      DeleteLocalRef: 23,
      IsSameObject: 24,
      NewLocalRef: 25,
      GetObjectClass: 31,
      IsInstanceOf: 32,
      GetMethodID: 33,
      NewObjectA: 30,
      GetStaticMethodID: 113,
      GetStaticFieldID: 144,
      NewString: 163,
      GetStringLength: 164,
      GetArrayLength: 171,
      GetObjectArrayElement: 173,
      RegisterNatives: 215,
      GetStringRegion: 220,
      ExceptionCheck: 228,
    }.freeze

    # Each Java type's JNI letter, Fiddle type, how a jvalue packs it, and
    # where its Call<Type>MethodA, CallStatic<Type>MethodA, and
    # Get(Static)<Type>Field are in the table.
    PRIMITIVES = {
      "boolean" => ["Z", Fiddle::TYPE_UCHAR, "C", 39, 119, 96, 146],
      "byte" => ["B", Fiddle::TYPE_CHAR, "c", 42, 122, 97, 147],
      "char" => ["C", Fiddle::TYPE_USHORT, "S<", 45, 125, 98, 148],
      "short" => ["S", Fiddle::TYPE_SHORT, "s<", 48, 128, 99, 149],
      "int" => ["I", Fiddle::TYPE_INT, "l<", 51, 131, 100, 150],
      "long" => ["J", Fiddle::TYPE_LONG_LONG, "q<", 54, 134, 101, 151],
      "float" => ["F", Fiddle::TYPE_FLOAT, "e", 57, 137, 102, 152],
      "double" => ["D", Fiddle::TYPE_DOUBLE, "E", 60, 140, 103, 153],
      "void" => ["V", Fiddle::TYPE_VOID, nil, 63, 143, nil, nil],
    }.freeze
    # An object's: Fiddle type, jvalue packing, and its table indexes.
    OBJECT = [nil, Fiddle::TYPE_VOIDP, "Q<", 36, 116, 95, 145].freeze

    # The box of each primitive, for an argument or result of type Object.
    BOXES = {
      "boolean" => "java/lang/Boolean",
      "byte" => "java/lang/Byte",
      "char" => "java/lang/Character",
      "short" => "java/lang/Short",
      "int" => "java/lang/Integer",
      "long" => "java/lang/Long",
      "float" => "java/lang/Float",
      "double" => "java/lang/Double",
    }.freeze

    STATIC = 0x0008 # java.lang.reflect.Modifier.STATIC

    @functions = {}
    @classes = {}
    @members = {}
    @proxies = {}
    @handles = 0
    @lock = Mutex.new

    class << self
      # The process's Java VM, a pointer: the one Java gave Fledge's
      # runtime as it loaded it, unless one was named with java_vm=.
      def java_vm
        @java_vm ||= begin
          library = Fiddle.dlopen("libfledgeruby.so")
          Fiddle::Function.new(library["fledge_ruby_java_vm"], [], P).call.to_i
        end
      end

      # Names the Java VM, for a process whose VM is not the runtime's.
      attr_writer :java_vm

      # This thread's JNIEnv, attaching the thread to Java first when Java
      # has not seen it, as a Ruby thread an app made.
      def env
        Thread.current.thread_variable_get(:fledge_jni_env) || begin
          slot = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          status = vm_function(6, [P, P, I], I).call(java_vm, slot, VERSION_1_6)
          vm_function(4, [P, P, P], I).call(java_vm, slot, nil) unless status.zero?
          Thread.current.thread_variable_set(:fledge_jni_env, slot[0, Fiddle::SIZEOF_VOIDP].unpack1("J"))
        end
      end

      # Calls the function at +index+ of JNIEnv's table, whose Fiddle
      # types are +arguments+ (JNIEnv's first) and +returns+, with this
      # thread's JNIEnv and +values+.
      def call(index, arguments, returns, *values)
        env = self.env
        function(index, arguments, returns).call(env, *values)
      end

      # The Java class named +name+, such as "android.widget.TextView" or
      # "android.view.View$OnClickListener", as a JNI::Class.
      def import(name)
        binary = name.to_s.tr(".", "/")
        @lock.synchronize { @classes[binary] ||= JNI::Class.new(binary, find_class(binary)) }
      end

      # A Java object of the interfaces named +interfaces+ whose methods
      # call +object+'s Ruby methods of the same names, or, given a Hash,
      # its values by their keys. A method +object+ does not have returns
      # nothing, or zero, or false; Object's own methods are the proxy's.
      def implement(*interfaces, object)
        handler = object.is_a?(Hash) ? Handler.new(object) : object
        handle = @lock.synchronize { @handles += 1 }
        @proxies[handle] = handler
        classes = interfaces.map { |name| import(name) }
        array = new_array(import("java.lang.Class"), classes)
        proxy_class.static_call("of", [J, :"java/lang/Class[]"], handle, array)
      end

      # Hands this thread to Android's Looper, from which every message
      # and every listener's call into Ruby then comes. The main thread
      # already loops, so this loop runs inside Android's, which Android
      # allows with a warning in the log (Looper.java, "Loop again would
      # have the queued messages be executed before this one
      # completed."): it never returns, since Android quits no main loop.
      # Ruby's lock is let go meanwhile, so its other threads run.
      def loop
        import("android.os.Looper").loop
      end

      # A Ruby value of the jobject +ref+, a local reference this deletes:
      # a String for a Java string, nil for null, else a JNI::Object.
      def from_java(ref)
        address = ref.to_i
        return nil if address.zero?

        if call(TABLE[:IsInstanceOf], [P, P, P], Fiddle::TYPE_UCHAR, address, string_class).nonzero?
          return to_ruby_string(address).tap { delete_local(address) }
        end

        JNI::Object.new(new_global(address)).tap { delete_local(address) }
      end

      # The jobject Java takes for +value+ as an object, and a local
      # reference to delete after the call when the bridge made one.
      def to_java(value)
        case value
        when nil then [0, nil]
        when JNI::Object, JNI::Class then [value.ref, nil]
        when ::String, ::Symbol then new_string(value.to_s).then { |ref| [ref, ref] }
        when true, false then box("boolean", value)
        when ::Integer then box("int", value)
        when ::Float then box("double", value)
        else raise Error, "#{value.inspect} is no Java object"
        end
      end

      # A Java string of +text+, a local reference.
      def new_string(text)
        units = text.encode(Encoding::UTF_16LE)
        checked { call(TABLE[:NewString], [P, P, I], P, units, units.bytesize / 2).to_i }
      end

      # The text of the Java string +ref+.
      def to_ruby_string(ref)
        length = call(TABLE[:GetStringLength], [P, P], I, ref)
        buffer = Fiddle::Pointer.malloc([length * 2, 1].max, Fiddle::RUBY_FREE)
        call(TABLE[:GetStringRegion], [P, P, I, I, P], Fiddle::TYPE_VOID, ref, 0, length, buffer)
        buffer[0, length * 2].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
      end

      # Raises a JavaError for an exception Java threw, after clearing it.
      def checked
        result = yield
        return result if call(TABLE[:ExceptionCheck], [P], Fiddle::TYPE_UCHAR).zero?

        throwable = call(TABLE[:ExceptionOccurred], [P], P).to_i
        call(TABLE[:ExceptionClear], [P], Fiddle::TYPE_VOID)
        message = string_of(direct("java/lang/Object", "toString", "()Ljava/lang/String;", throwable))
        raise JavaError.new(message, JNI::Object.new(new_global(throwable)).tap { delete_local(throwable) })
      end

      # Whether the references +one+ and +other+ are to the same object.
      def same?(one, other)
        call(TABLE[:IsSameObject], [P, P, P], Fiddle::TYPE_UCHAR, one, other) != 0
      end

      # A new global reference to +ref+.
      def new_global(ref)
        call(TABLE[:NewGlobalRef], [P, P], P, ref).to_i
      end

      # Deletes the local reference +ref+, unless it is null.
      def delete_local(ref)
        call(TABLE[:DeleteLocalRef], [P, P], Fiddle::TYPE_VOID, ref) unless ref.to_i.zero?
      end

      # Deletes the global reference +ref+.
      def delete_global(ref)
        call(TABLE[:DeleteGlobalRef], [P, P], Fiddle::TYPE_VOID, ref)
      end

      # The methods, constructors (+:new+), or fields (+:fields+) named
      # +name+ of the class +klass+, each a Member, read once by
      # reflection.
      def members(klass, name)
        (@members[klass.name] ||= {})[name] ||= reflect(klass, name)
      end

      # Calls the method +name+, of JNI signature +signature+, of the class
      # +owner+, on +target+, by its JNI ID, with no arguments: what the
      # bridge asks reflection, which it cannot ask reflectively. Returns
      # the result, a local reference for an object, or +returns+'s.
      def direct(owner, name, signature, target, returns: OBJECT)
        key = [owner, name, signature]
        id = (@direct ||= {})[key] ||= call(TABLE[:GetMethodID], [P, P, P, P], P, import(owner).ref, name, signature).to_i
        result = checked { call(returns[3], [P, P, P, P], returns[1], target, id, nil) }
        returns.equal?(OBJECT) ? result.to_i : result
      end

      # The JNI descriptor of the type +name+, as Class.getName spells it:
      # "I" for "int", "Ljava/lang/String;" for "java.lang.String",
      # "[I" for "[I".
      def descriptor(name)
        return PRIMITIVES.fetch(name).first if PRIMITIVES.key?(name)
        return name.tr(".", "/") if name.start_with?("[")

        "L#{name.tr('.', '/')};"
      end

      # The text of the Java string +ref+, a local reference this deletes.
      def string_of(ref)
        to_ruby_string(ref).tap { delete_local(ref) }
      end

      # The name of the class +ref+, a local reference this deletes, as
      # Class.getName gives it: "int", "java.lang.String".
      def class_name_of(ref)
        string_of(direct("java/lang/Class", "getName", "()Ljava/lang/String;", ref)).tap { delete_local(ref) }
      end

      # The box of +value+ as the primitive +type+, a local reference.
      def box(type, value)
        klass = import(BOXES.fetch(type))
        ref = klass.static_call("valueOf", [type], value).then { |boxed| boxed.is_a?(JNI::Object) ? boxed : nil }
        ref ? [call(TABLE[:NewLocalRef], [P, P], P, ref.ref).to_i, :local] : raise(Error, "Java has no #{type} of #{value}")
      end

      # A Java array of +items+, of the class +klass+, a JNI::Object.
      def new_array(klass, items)
        array = checked { call(172, [P, I, P, P], P, items.size, klass.ref, 0).to_i }
        items.each_with_index do |item, index|
          ref, made = to_java(item)
          call(174, [P, P, I, P], Fiddle::TYPE_VOID, array, index, ref)
          delete_local(ref) if made
        end
        JNI::Object.new(new_global(array)).tap { delete_local(array) }
      end

      # The Java values of a Java array +ref+, a local reference.
      def array_items(ref)
        size = call(TABLE[:GetArrayLength], [P, P], I, ref)
        Array.new(size) { |index| call(TABLE[:GetObjectArrayElement], [P, P, I], P, ref, index).to_i }
      end

      # The Ruby object a proxy's handle stands for.
      def proxy(handle)
        @proxies.fetch(handle)
      end

      # The function at +index+ of JNIEnv's table, as Fiddle calls it.
      def function(index, arguments, returns)
        key = [index, arguments, returns]
        @functions[key] ||= begin
          table = Fiddle::Pointer.new(env_table)
          address = table[index * Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J")
          Fiddle::Function.new(address, arguments, returns)
        end
      end

      private def env_table
        Fiddle::Pointer.new(env)[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
      end

      private def vm_function(index, arguments, returns)
        table = Fiddle::Pointer.new(java_vm)[0, Fiddle::SIZEOF_VOIDP].unpack1("J")
        address = Fiddle::Pointer.new(table)[index * Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_VOIDP].unpack1("J")
        Fiddle::Function.new(address, arguments, returns)
      end

      private def find_class(binary)
        local = call(TABLE[:FindClass], [P, P], P, binary).to_i
        if call(TABLE[:ExceptionCheck], [P], Fiddle::TYPE_UCHAR).nonzero?
          call(TABLE[:ExceptionClear], [P], Fiddle::TYPE_VOID)
          local = load_class(binary)
        end
        new_global(local).tap { delete_local(local) }
      end

      # A class FindClass cannot see from this thread, as an app's own
      # from a thread Ruby made: by the runtime's class loader.
      private def load_class(binary)
        raise Error, "Java has no class #{binary.tr('/', '.')}" unless @loader

        name = new_string(binary.tr("/", "."))
        checked { call(OBJECT[3], [P, P, P, P], P, @loader, @load_class, [name].pack("Q<")).to_i }.tap { delete_local(name) }
      end

      private def string_class
        @string_class ||= import("java.lang.String").ref
      end

      private def proxy_class
        @proxy_class ||= import("org.setdef.fledge.RubyProxy").tap { |klass| register(klass) }
      end

      # Gives RubyProxy.call its code: Ruby's, through a Fiddle closure.
      private def register(klass)
        @closure = Fiddle::Closure::BlockCaller.new(P, [P, P, J, P, P, P]) do |_env, _class, handle, proxy, method, arguments|
          Handler.invoke(handle, proxy.to_i, method.to_i, arguments.to_i)
        end
        name = Fiddle::Pointer["call"]
        signature = Fiddle::Pointer["(JLjava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;"]
        @native = [name.to_i, signature.to_i, @closure.to_i].pack("Q<3")
        @native_strings = [name, signature]
        checked { call(TABLE[:RegisterNatives], [P, P, P, I], I, klass.ref, @native, 1) }
      end

      GETTERS = {
        new: ["getConstructors", "()[Ljava/lang/reflect/Constructor;"],
        fields: ["getFields", "()[Ljava/lang/reflect/Field;"],
      }.freeze

      private def reflect(klass, name)
        getter, signature = GETTERS.fetch(name) { ["getMethods", "()[Ljava/lang/reflect/Method;"] }
        array = direct("java/lang/Class", getter, signature, klass.ref)
        found = array_items(array).filter_map do |member|
          member_name = string_of(direct("java/lang/reflect/Member", "getName", "()Ljava/lang/String;", member))
          next Member.read(member, member_name, name) if name.is_a?(Symbol) || member_name == name

          delete_local(member)
          nil
        end
        found.tap { delete_local(array) }
      end
    end

    # A method, constructor, or field of a Java class, as reflection gives
    # it: its name, its parameters' and result's Java types, whether it is
    # static, and its JNI ID.
    class Member < Data.define(:name, :parameters, :returns, :static, :id, :field)
      # The Member of the reflected method, constructor, or field +ref+,
      # named +name+, a local reference this deletes; +kind+ is +:new+ for
      # a constructor and +:fields+ for a field.
      def self.read(ref, name, kind)
        static = JNI.direct("java/lang/reflect/Member", "getModifiers", "()I", ref, returns: PRIMITIVES.fetch("int")).anybits?(STATIC)
        if kind == :fields
          type = JNI.class_name_of(JNI.direct("java/lang/reflect/Field", "getType", "()Ljava/lang/Class;", ref))
          id = JNI.call(TABLE[:FromReflectedField], [P, P], P, ref).to_i
          return new(name:, parameters: [], returns: type, static:, id:, field: true).tap { JNI.delete_local(ref) }
        end
        types = JNI.direct("java/lang/reflect/Executable", "getParameterTypes", "()[Ljava/lang/Class;", ref)
        parameters = JNI.array_items(types).map { |type| JNI.class_name_of(type) }
        JNI.delete_local(types)
        returns = (kind == :new) ? "void" : JNI.class_name_of(JNI.direct("java/lang/reflect/Method", "getReturnType", "()Ljava/lang/Class;", ref))
        id = JNI.call(TABLE[:FromReflectedMethod], [P, P], P, ref).to_i
        JNI.delete_local(ref)
        new(name: (kind == :new) ? :new : name, parameters:, returns:, static:, id:, field: false)
      end

      # How well +arguments+ fit the parameters: nil when they do not,
      # else a cost, lower for a closer fit.
      def fit(arguments)
        return nil unless arguments.size == parameters.size

        parameters.zip(arguments).sum do |type, value|
          cost = Member.cost(type, value)
          return nil unless cost

          cost
        end
      end

      # The cost of passing +value+ as a parameter of Java type +type+.
      def self.cost(type, value)
        case value
        when true, false then { "boolean" => 0, "java.lang.Boolean" => 1, "java.lang.Object" => 3 }[type]
        when ::Integer then {
"int" => 0,
"long" => 1,
"short" => 2,
"byte" => 2,
"float" => 3,
"double" => 3,
"java.lang.Integer" => 4,
"java.lang.Object" => 5,
"java.lang.Number" => 5,
"char" => 6,
}[type]
        when ::Float then { "double" => 0, "float" => 1, "java.lang.Double" => 2, "java.lang.Object" => 3 }[type]
        when ::String, ::Symbol then {
"java.lang.String" => 0,
"java.lang.CharSequence" => 1,
"java.lang.Object" => 2,
"char" => ((value.to_s.size == 1) ? 3 : nil),
}[type]
        when nil then PRIMITIVES.key?(type) ? nil : 1
        when JNI::Object, JNI::Class then value.instance_of_class?(type) ? 0 : nil
        end
      end
    end

    # What JNI.implement gives a Hash of the interface's methods.
    class Handler
      def initialize(methods)
        @methods = methods.transform_keys(&:to_s)
      end

      def respond_to_missing?(name, include_private = false)
        @methods.key?(name.to_s) || super
      end

      def method_missing(name, ...)
        @methods.key?(name.to_s) ? @methods.fetch(name.to_s).call(...) : super
      end

      # Runs the call of +method+ of the proxy numbered +handle+ with the
      # Java array +arguments+, and returns the jobject Java boxes or
      # unboxes for the method's result. An exception would unwind through
      # Java's frames, which Ruby must never do, so it is printed, as Ruby
      # prints one its program does not rescue, and the method returns
      # null, zero, or false; SystemExit ends the process with its status.
      def self.invoke(handle, proxy, method, arguments)
        name = JNI.string_of(JNI.direct("java/lang/reflect/Member", "getName", "()Ljava/lang/String;", method))
        returns = JNI.class_name_of(JNI.direct("java/lang/reflect/Method", "getReturnType", "()Ljava/lang/Class;", method))
        values = arguments.zero? ? [] : JNI.array_items(arguments).map { |ref| unbox(JNI.from_java(ref)) }
        result = respond(JNI.proxy(handle), name, values, handle, proxy)
        result_ref(returns, result)
      rescue SystemExit => e
        $stdout.flush
        $stderr.flush
        Kernel.exit!(e.status)
      rescue Exception => e
        warn(e.full_message(highlight: false))
        returns ? result_ref(returns, nil) : 0
      end

      # What +object+'s method +name+ answers, or Object's own method of
      # the proxy +proxy+, numbered +handle+.
      def self.respond(object, name, values, handle, proxy)
        return object.public_send(name, *values) if object.respond_to?(name)

        case name
        when "hashCode" then handle & 0x7fffffff
        when "equals" then values.first.respond_to?(:ref) && JNI.same?(values.first.ref, proxy)
        when "toString" then "Ruby #{object.class}"
        end
      end

      # The Ruby number or boolean a boxed primitive holds, else +value+.
      def self.unbox(value)
        return value unless value.is_a?(JNI::Object)

        {
"java.lang.Integer" => "intValue",
"java.lang.Long" => "longValue",
"java.lang.Boolean" => "booleanValue",
"java.lang.Float" => "floatValue",
"java.lang.Double" => "doubleValue",
"java.lang.Short" => "shortValue",
"java.lang.Byte" => "byteValue",
}.each do |box, getter|
          return value.public_send(getter) if value.instance_of_class?(box)
        end
        value
      end

      # A local reference for +result+ as the Java type +returns+, boxed
      # for a primitive, with zero or false for nil.
      def self.result_ref(returns, result)
        return 0 if returns == "void"

        if PRIMITIVES.key?(returns)
          value = result.nil? ? { "float" => 0.0, "double" => 0.0 }.fetch(returns, 0) : result
          value = result ? true : false if returns == "boolean"
          value = value.ord if returns == "char" && value.is_a?(::String)
          return JNI.box(returns, value).first
        end
        ref, made = JNI.to_java(result)
        made ? ref : JNI.call(TABLE[:NewLocalRef], [P, P], P, ref).to_i
      end
    end

    # A Java object as Ruby sees it: each Java method is a Ruby method of
    # the same name (see JNI). It holds a global reference until Ruby
    # collects it.
    class Object
      # Deletes an object's global reference.
      class Release
        def initialize(ref)
          @ref = ref
        end

        def call(*)
          JNI.delete_global(@ref)
        end
      end

      # The global reference, a jobject.
      attr_reader :ref

      def initialize(ref)
        @ref = ref
        ObjectSpace.define_finalizer(self, Release.new(ref))
      end

      # The object's class, a JNI::Class.
      def java_class
        local = JNI.call(TABLE[:GetObjectClass], [P, P], P, ref).to_i
        name = JNI::Class.name_of(local)
        JNI.delete_local(local)
        JNI.import(name)
      end

      # Whether the object is an instance of the class named +name+.
      def instance_of_class?(name)
        return false if PRIMITIVES.key?(name)

        JNI.call(TABLE[:IsInstanceOf], [P, P, P], Fiddle::TYPE_UCHAR, ref, JNI.import(name).ref) != 0
      end

      # The Java values of this object, a Java array.
      def items
        JNI.array_items(ref).map { |item| JNI.from_java(item) }
      end

      def method_missing(name, *arguments)
        java_class.call_on(ref, name.to_s, arguments)
      end

      def respond_to_missing?(name, include_private = false)
        !JNI.members(java_class, name.to_s).empty? || super
      end

      def to_s
        JNI.string_of(JNI.direct("java/lang/Object", "toString", "()Ljava/lang/String;", ref))
      end

      def inspect
        "#<#{java_class.name.tr('/', '.')} #{self}>"
      end

      def ==(other)
        other.respond_to?(:ref) && JNI.same?(ref, other.ref)
      end
    end

    # A Java class: its static methods and fields are Ruby methods of the
    # same names, and +new+ calls a constructor.
    class Class
      # The class's binary name, such as "android/widget/TextView".
      attr_reader :name

      # The global reference to the class.
      attr_reader :ref

      def initialize(name, ref)
        @name = name
        @ref = ref
      end

      # The binary name of the class +local+, a jclass.
      def self.name_of(local)
        JNI.string_of(JNI.direct("java/lang/Class", "getName", "()Ljava/lang/String;", local)).tr(".", "/")
      end

      # A new object of this class, by the constructor that takes +arguments+.
      def new(*arguments)
        member = pick(JNI.members(self, :new), arguments, "constructor")
        with_values(member, arguments) do |values|
          JNI.from_java(JNI.checked { JNI.call(TABLE[:NewObjectA], [P, P, P, P], P, ref, member.id, values).to_i })
        end
      end

      # Calls the static method +name+ whose parameters are the Java types
      # +types+ (a Fiddle type or a binary name, for the bridge's own
      # calls), or else the one that takes +arguments+.
      def static_call(name, types, *arguments)
        candidates = JNI.members(self, name).select(&:static)
        member = candidates.find { |each| each.parameters.size == types.size } if types.any? { |type| !type.is_a?(::String) }
        member ||= pick(candidates, arguments, "static method #{name}")
        invoke(member, ref, arguments, static: true)
      end

      # Calls the method +name+ of the object +target+, a jobject, that
      # takes +arguments+. +raw+ returns the result's local reference.
      def call_on(target, name, arguments, raw: false)
        member = pick(JNI.members(self, name).reject(&:static), arguments, "method #{name}")
        invoke(member, target, arguments, static: false, raw:)
      end

      def method_missing(name, *arguments)
        statics = JNI.members(self, name.to_s).select(&:static)
        return invoke(pick(statics, arguments, "static method #{name}"), ref, arguments, static: true) unless statics.empty?

        field = JNI.members(self, :fields).find { |each| each.name == name.to_s && each.static }
        return read_static(field) if field && arguments.empty?

        super
      end

      def respond_to_missing?(name, include_private = false)
        JNI.members(self, name.to_s).any?(&:static) || JNI.members(self, :fields).any? { |each| each.name == name.to_s } || super
      end

      def inspect
        "#<Java class #{name.tr('/', '.')}>"
      end

      # Whether this is, or is a subclass of, the class named +other+.
      def instance_of_class?(other)
        other == "java.lang.Class" || other == "java.lang.Object"
      end

      private def pick(candidates, arguments, what)
        fitting = candidates.filter_map { |member| (cost = member.fit(arguments)) && [cost, member] }
        raise Error, "#{name.tr('/', '.')} has no #{what} that takes #{arguments.map(&:class).join(', ')}" if fitting.empty?

        fitting.min_by(&:first).last
      end

      private def invoke(member, target, arguments, static:, raw: false)
        type = JNI::PRIMITIVES.fetch(member.returns, JNI::OBJECT)
        index = static ? type[4] : type[3]
        with_values(member, arguments) do |values|
          result = JNI.checked { JNI.call(index, [P, P, P, P], type[1], target, member.id, values) }
          next result if raw
          next nil if member.returns == "void"
          next result != 0 if member.returns == "boolean"
          next result.chr(Encoding::UTF_8) if member.returns == "char"

          JNI::PRIMITIVES.key?(member.returns) ? result : JNI.from_java(result.to_i)
        end
      end

      # The value of the static +field+. FromReflectedField's ID does not
      # initialize the class, which Android's ART leaves, as the JNI
      # specification allows, with every static field at zero until
      # something does (+android.R$layout.simple_list_item_1+ read as 0);
      # GetStaticFieldID is the call the specification says initializes
      # it, so the bridge asks it for the ID.
      private def read_static(field)
        type = JNI::PRIMITIVES.fetch(field.returns, JNI::OBJECT)
        id = JNI.checked { JNI.call(TABLE[:GetStaticFieldID], [P, P, P, P], P, ref, field.name, JNI.descriptor(field.returns)).to_i }
        result = JNI.checked { JNI.call(type[6], [P, P, P], type[1], ref, id) }
        return result != 0 if field.returns == "boolean"

        JNI::PRIMITIVES.key?(field.returns) ? result : JNI.from_java(result.to_i)
      end

      # Packs +arguments+ as the jvalues +member+'s parameters take, and
      # deletes the local references the bridge made for them after the
      # block.
      private def with_values(member, arguments)
        made = []
        packed = member.parameters.zip(arguments).map do |type, value|
          primitive = JNI::PRIMITIVES[type]
          next [jvalue(type, value)].pack(primitive[2]).ljust(8, "\0") if primitive

          ref, local = JNI.to_java(value)
          made << ref if local
          [ref].pack("Q<")
        end
        yield packed.empty? ? nil : packed.join
      ensure
        made&.each { |ref| JNI.delete_local(ref) }
      end

      private def jvalue(type, value)
        case type
        when "boolean" then value ? 1 : 0
        when "char" then value.is_a?(::String) ? value.ord : value
        when "float", "double" then Float(value)
        else Integer(value)
        end
      end
    end

    # The class loader of Fledge's runtime, for the app's own classes,
    # which FindClass does not see from a thread Ruby made.
    def self.remember_loader
      fledge = import("org.setdef.fledge.FledgeRuby")
      loader = call(OBJECT[3], [P, P, P, P], P, fledge.ref,
        call(TABLE[:GetMethodID], [P, P, P, P], P, import("java.lang.Class").ref, "getClassLoader", "()Ljava/lang/ClassLoader;"), nil).to_i
      @load_class = call(TABLE[:GetMethodID], [P, P, P, P], P, import("java.lang.ClassLoader").ref, "loadClass",
        "(Ljava/lang/String;)Ljava/lang/Class;").to_i
      @loader = new_global(loader).tap { delete_local(loader) }
    rescue Error
      @loader = nil
    end
  end
end

# The runtime's class loader, read on the main thread as the app starts,
# where FindClass sees the app's classes.
Fledge::JNI.remember_loader if RUBY_PLATFORM.include?("android")
