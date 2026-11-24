# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fiddle"

module Fledge
  # Ruby's way to the Objective-C runtime, and through it to UIKit, on
  # iOS (doc/contributors/design/phone-widgets.md). It is Fledge's
  # bridge, not a layer of widgets: an app makes UIKit's own objects and
  # sends them UIKit's own messages, as Apple documents them, and
  # defines its delegates as Objective-C classes written in Ruby.
  #
  # A message is a method call whose name is the selector's first part
  # and whose keywords are the rest, as RubyMotion spells them;
  # <tt>name=</tt> sends <tt>setName:</tt>:
  #
  #   table.dequeueReusableCellWithIdentifier("item", forIndexPath: path)
  #   label.text = "Hello"
  #
  # A class of UIKit's is a constant here, and a Ruby class that inherits
  # from one is an Objective-C class of that name, whose methods marked
  # with +objc_method+ Objective-C can send:
  #
  #   class SceneDelegate < Fledge::ObjC::UIResponder
  #     objc_protocols "UIWindowSceneDelegate"
  #
  #     objc_method def scene(scene, willConnectToSession: session, options: options)
  #       ...
  #     end
  #   end
  #
  # UIKit is the main thread's alone, so an app that draws its screen
  # runs its Ruby on that thread (+kind: windowed+ in fledge.yml) and
  # hands it to UIKit with ObjC.application_main, which returns only if
  # UIKit cannot start.
  module ObjC
    # libobjc, which every app links through Foundation.
    LIBRARY = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")

    # Raised for what the bridge cannot do: a selector the receiver does
    # not answer, or a type in its encoding Fiddle cannot pass.
    class Error < StandardError; end

    # The C functions the bridge calls, from libobjc and libdispatch.
    module Runtime
      P = Fiddle::TYPE_VOIDP
      I = Fiddle::TYPE_INT
      B = Fiddle::TYPE_BOOL

      def self.function(name, args, ret, handle = LIBRARY)
        Fiddle::Function.new(handle[name], args, ret, need_gvl: true)
      end

      GET_CLASS = function("objc_getClass", [P], P)
      GET_PROTOCOL = function("objc_getProtocol", [P], P)
      REGISTER_NAME = function("sel_registerName", [P], P)
      SELECTOR_NAME = function("sel_getName", [P], P)
      OBJECT_CLASS = function("object_getClass", [P], P)
      CLASS_NAME = function("class_getName", [P], P)
      SUPERCLASS = function("class_getSuperclass", [P], P)
      META_CLASS = function("class_isMetaClass", [P], B)
      INSTANCE_METHOD = function("class_getInstanceMethod", [P, P], P)
      METHOD_TYPES = function("method_getTypeEncoding", [P], P)
      ALLOCATE_CLASS = function("objc_allocateClassPair", [P, P, Fiddle::TYPE_SIZE_T], P)
      REGISTER_CLASS = function("objc_registerClassPair", [P], Fiddle::TYPE_VOID)
      ADD_METHOD = function("class_addMethod", [P, P, P, P], B)
      ADD_PROTOCOL = function("class_addProtocol", [P, P], B)
      PROTOCOL_METHODS = function("protocol_copyMethodDescriptionList", [P, B, B, P], P)
      PROTOCOL_PROTOCOLS = function("protocol_copyProtocolList", [P, P], P)
      RETAIN = function("objc_retain", [P], P)
      FREE = function("free", [P], Fiddle::TYPE_VOID, Fiddle::Handle::DEFAULT)

      # objc_msgSend, whose type is each method's own.
      MSG_SEND = LIBRARY["objc_msgSend"]
      # objc_msgSendSuper, for a Ruby class's dealloc.
      MSG_SEND_SUPER = LIBRARY["objc_msgSendSuper"]
      # objc_release, which the main queue calls for an object Ruby let go.
      RELEASE = LIBRARY["objc_release"]
      # The main queue, which dispatch_get_main_queue() names.
      MAIN_QUEUE = Fiddle::Handle::DEFAULT["_dispatch_main_q"]
      DISPATCH_ASYNC = function("dispatch_async_f", [P, P, P], Fiddle::TYPE_VOID, Fiddle::Handle::DEFAULT)
    end
    private_constant :Runtime

    # The Fiddle type for each type code of an encoding Fiddle can pass:
    # Apple's "Type Encodings", where +l+ and +L+ are 32 bits on every
    # platform and +q+ and +Q+ are 64.
    FIDDLE_TYPES = {
      "c" => Fiddle::TYPE_CHAR,
      "C" => Fiddle::TYPE_UCHAR,
      "s" => Fiddle::TYPE_SHORT,
      "S" => Fiddle::TYPE_USHORT,
      "i" => Fiddle::TYPE_INT,
      "I" => Fiddle::TYPE_UINT,
      "l" => Fiddle::TYPE_INT32_T,
      "L" => Fiddle::TYPE_UINT32_T,
      "q" => Fiddle::TYPE_LONG_LONG,
      "Q" => Fiddle::TYPE_ULONG_LONG,
      "f" => Fiddle::TYPE_FLOAT,
      "d" => Fiddle::TYPE_DOUBLE,
      "B" => Fiddle::TYPE_BOOL,
      "v" => Fiddle::TYPE_VOID,
      "*" => Fiddle::TYPE_VOIDP,
      "@" => Fiddle::TYPE_VOIDP,
      "#" => Fiddle::TYPE_VOIDP,
      ":" => Fiddle::TYPE_VOIDP,
      "^" => Fiddle::TYPE_VOIDP,
    }.freeze

    # The method families whose result the caller owns, from clang's
    # rules for automatic reference counting, as rubicon-objc reads them.
    OWNING_FAMILIES = %w[alloc new copy mutableCopy init].freeze

    @functions = {} # the objc_msgSend of each signature
    @classes = {} # the Ruby class of each Objective-C class, by pointer
    @instances = {} # each live instance of a class defined in Ruby, by pointer
    @closures = [] # each method a Ruby class gave Objective-C, kept from the collector

    # The type encodings of the methods of the UIKit protocols a Ruby
    # class most often implements, for when the Objective-C runtime has
    # no such protocol to give them (see objc_protocols). From UIKit's
    # headers, for 64-bit ARM: +q+ is NSInteger, +B+ is BOOL.
    PROTOCOL_ENCODINGS = {
      "UITableViewDataSource" => {
        "tableView:numberOfRowsInSection:" => "q32@0:8@16q24",
        "tableView:cellForRowAtIndexPath:" => "@32@0:8@16@24",
        "numberOfSectionsInTableView:" => "q24@0:8@16",
        "tableView:titleForHeaderInSection:" => "@32@0:8@16q24",
        "tableView:canEditRowAtIndexPath:" => "B32@0:8@16@24",
        "tableView:commitEditingStyle:forRowAtIndexPath:" => "v40@0:8@16q24@32",
        "tableView:moveRowAtIndexPath:toIndexPath:" => "v40@0:8@16@24@32",
      },
      "UIApplicationDelegate" => {
        "application:didFinishLaunchingWithOptions:" => "B32@0:8@16@24",
        "application:configurationForConnectingSceneSession:options:" => "@40@0:8@16@24@32",
      },
      "UIWindowSceneDelegate" => {
        "scene:willConnectToSession:options:" => "v40@0:8@16@24@32",
        "sceneDidBecomeActive:" => "v24@0:8@16",
        "sceneWillResignActive:" => "v24@0:8@16",
        "sceneDidDisconnect:" => "v24@0:8@16",
      },
    }.freeze

    class << self
      # Loads the framework +name+ into the process, as dlopen does the
      # file of its path in the system's Frameworks folder, which defines
      # its classes and protocols for the Objective-C runtime: a process
      # whose own code names none of UIKit's does not have it loaded, and
      # +objc_getClass+ finds no UIResponder in it. Returns whether the
      # framework loaded.
      def load_framework(name)
        Fiddle.dlopen("/System/Library/Frameworks/#{name}.framework/#{name}")
        true
      rescue Fiddle::DLError
        false
      end

      # The Objective-C class named +name+, as the Ruby class whose
      # instances wrap its objects, or nil when there is none.
      def class_named(name)
        pointer = Runtime::GET_CLASS.call(name.to_s)
        pointer.null? ? nil : ruby_class(pointer.to_i)
      end

      # The selector named +name+, such as "setText:".
      def selector(name)
        Runtime::REGISTER_NAME.call(name.to_s).to_i
      end

      # Gives the main thread to UIKit: UIApplicationMain, with the
      # application delegate +delegate+, a class defined in Ruby. Every
      # class defined in Ruby is registered first, so that UIKit finds
      # the scene delegate Info.plist names. Returns only if UIKit does,
      # with its status. Ruby's other threads run meanwhile, since the
      # call lets Ruby's lock go, and each message UIKit sends a Ruby
      # class takes it again.
      def application_main(delegate)
        main = Fiddle::Function.new(Fiddle::Handle::DEFAULT["UIApplicationMain"],
          [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
        name = string(delegate.objc_name)
        main.call(0, nil, nil, name.objc_pointer)
      end

      # An NSString of +text+, which the returned object owns.
      def string(text)
        bytes = text.to_s.encode(Encoding::UTF_8)
        class_named("NSString").alloc.initWithBytes(bytes, length: bytes.bytesize, encoding: 4)
      end

      # An NSArray of +items+, each converted as an object argument is.
      def array(items)
        kept = [] # the objects made for +items+, alive until the array holds them
        objects = items.map { |item| object_argument(item, kept) }
        buffer = Fiddle::Pointer.malloc([objects.size, 1].max * Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        buffer[0, objects.size * Fiddle::SIZEOF_VOIDP] = objects.pack("J*")
        class_named("NSArray").arrayWithObjects(buffer, count: objects.size).tap { kept.clear }
      end

      # The Ruby object for the Objective-C object at +pointer+, or nil
      # for nil. The caller owns a reference when +owned+, which the
      # returned object then holds; otherwise it takes one of its own.
      # Each holds its reference until Ruby collects it, then gives it
      # back on the main queue, where UIKit wants its objects released.
      def wrap(pointer, owned: false)
        address = pointer.to_i
        return nil if address.zero?
        return @instances.fetch(address) if @instances.key?(address)

        isa = Runtime::OBJECT_CLASS.call(address).to_i
        return ruby_class(address) if Runtime::META_CLASS.call(isa)

        klass = ruby_class(isa)
        return adopt(klass, address) if klass.defined_in_ruby?

        Runtime::RETAIN.call(address) unless owned
        klass.allocate.tap { |object| object.__send__(:objc_hold, address) }
      end

      # The pointer to pass for +value+ as an object (@, #) argument:
      # an NSString for a String, an NSArray for an Array, the class for
      # a Ruby class of an Objective-C one, and nil for nil. An object
      # made for the call goes in +kept+, which the caller holds until
      # the call returns.
      def object_argument(value, kept = [])
        case value
        when nil then 0
        when Object, ::Class then value.objc_pointer
        when ::String, ::Symbol then string(value).tap { |object| kept << object }.objc_pointer
        when ::Array then array(value).tap { |object| kept << object }.objc_pointer
        else raise Error, "#{value.inspect} is no Objective-C object"
        end
      end

      # Sends +selector+ to the object at +receiver+, with +arguments+
      # converted by the method's encoding, and converts its result.
      def send_message(receiver, selector, arguments)
        sel = selector(selector)
        encoding = encoding_of(receiver, sel) || raise(NoMethodError,
          "#{class_name(Runtime::OBJECT_CLASS.call(receiver).to_i)} does not answer #{selector}")
        types = ObjC.parse(encoding)
        returns, *parameters = types
        parameters = parameters.drop(2)
        raise ArgumentError, "#{selector} takes #{parameters.size} arguments, not #{arguments.size}" unless parameters.size == arguments.size

        kept = [] # the objects made for the arguments, alive until the call returns
        values = parameters.zip(arguments).map { |type, value| to_c(type, value, kept) }
        result = function(returns, parameters).call(receiver, sel, *values)
        kept.clear
        from_c(returns, result, owned: owning?(selector))
      end

      # Whether the caller owns what +selector+ returns.
      def owning?(selector)
        OWNING_FAMILIES.any? { |family| family?(selector, family) }
      end

      # Whether +selector+ is an init method, which consumes its receiver.
      def init?(selector)
        family?(selector, "init")
      end

      # The type codes of an Objective-C type encoding, without its
      # qualifiers and offsets: <tt>"v24@0:8@16"</tt> is
      # <tt>["v", "@", ":", "@"]</tt>.
      def parse(encoding)
        codes = []
        index = 0
        while index < encoding.size
          index += 1 while "rnNoORVA".include?(encoding[index])
          start = index
          index = skip(encoding, index)
          codes << encoding[start...index]
          index += 1 while encoding[index]&.match?(/[\d-]/)
        end
        codes
      end

      # The value Fiddle passes for +value+, as argument +type+, with an
      # object made for it in +kept+.
      def to_c(type, value, kept = [])
        case type[0]
        when "@", "#" then object_argument(value, kept)
        when ":" then value.nil? ? 0 : selector(value)
        when "B" then value ? true : false
        when "c", "C" then (value == true) ? 1 : (value || 0)
        when "*", "^" then value.nil? ? 0 : value
        when "d", "f" then Float(value)
        when *FIDDLE_TYPES.keys then Integer(value)
        else raise Error, "Fiddle cannot pass an argument of type #{type}"
        end
      end

      # The Ruby value of a result of +type+.
      def from_c(type, value, owned: false)
        case type[0]
        when "v" then nil
        when "@" then wrap(value, owned:)
        when "#" then value.to_i.zero? ? nil : ruby_class(value.to_i)
        when ":" then value.to_i.zero? ? nil : Runtime::SELECTOR_NAME.call(value).to_s.to_sym
        when "*" then value.to_i.zero? ? nil : Fiddle::Pointer.new(value.to_i).to_s
        when "^" then Fiddle::Pointer.new(value.to_i)
        when "B" then value == true || (value.is_a?(Integer) && !value.zero?)
        else value
        end
      end

      # The Fiddle type of type code +type+, or an Error naming it.
      def fiddle_type(type)
        FIDDLE_TYPES.fetch(type[0]) { raise Error, "Fiddle cannot pass a value of type #{type}" }
      end

      # The Ruby class of the Objective-C class at +pointer+, made, with
      # its superclasses, the first time it is asked for, and named in
      # this module when its name is a Ruby constant's.
      def ruby_class(pointer)
        @classes.fetch(pointer) do
          superclass = Runtime::SUPERCLASS.call(pointer).to_i
          parent = superclass.zero? ? Object : ruby_class(superclass)
          name = class_name(pointer)
          klass = ::Class.new(parent)
          klass.__send__(:objc_bind, pointer, name)
          @classes[pointer] = klass
          const_set(name, klass) if name.match?(/\A[A-Z]\w*\z/) && !const_defined?(name, false)
          klass
        end
      end

      # Loads the Objective-C class a constant of this module names.
      def const_missing(name)
        class_named(name) || super
      end

      # The encoding of the method +sel+ answers on the object at
      # +receiver+, or nil when it answers none.
      def encoding_of(receiver, sel)
        method = Runtime::INSTANCE_METHOD.call(Runtime::OBJECT_CLASS.call(receiver), sel)
        method.null? ? nil : Runtime::METHOD_TYPES.call(method).to_s
      end

      # The encoding a protocol of +protocols+, or one they adopt, gives
      # the instance method +selector+, or nil.
      def protocol_encoding(protocols, selector)
        sel = selector(selector)
        protocols.each do |name|
          protocol = Runtime::GET_PROTOCOL.call(name.to_s)
          found = protocol.null? ? PROTOCOL_ENCODINGS.dig(name.to_s, selector.to_s) : protocol_types(protocol.to_i, sel)
          return found if found
        end
        nil
      end

      # Records the instance of a Ruby class at +address+, made by
      # Objective-C, which no Ruby object yet stands for.
      def adopt(klass, address)
        @instances[address] = klass.allocate.tap { |object| object.__send__(:objc_hold, address, held: false) }
      end

      # Forgets the instance at +address+, which Objective-C deallocates.
      def forget(address)
        @instances.delete(address)
      end

      # Keeps +closure+, a method Objective-C may call, from the collector.
      def keep(closure)
        @closures << closure
        closure
      end

      # Records +klass+, defined in Ruby, as the class at +pointer+.
      def register(pointer, klass)
        @classes[pointer] = klass
      end

      # The Objective-C class name of the class at +pointer+.
      def class_name(pointer)
        Runtime::CLASS_NAME.call(pointer).to_s
      end

      private def function(returns, parameters)
        key = [returns, *parameters].join(",")
        @functions[key] ||= Fiddle::Function.new(Runtime::MSG_SEND,
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, *parameters.map { |type| fiddle_type(type) }], fiddle_type(returns))
      end

      private def family?(selector, family)
        name = selector.to_s.sub(/\A_+/, "")
        name.start_with?(family) && !name[family.size]&.match?(/[a-z]/)
      end

      private def skip(encoding, index)
        case encoding[index]
        when "^" then skip(encoding, index + 1)
        when "@" then skip_object(encoding, index)
        when "{", "(", "[" then balanced(encoding, index)
        when "b" then (index + 1).step.find { |at| !encoding[at]&.match?(/\d/) }
        else index + 1
        end
      end

      private def skip_object(encoding, index)
        case encoding[index + 1]
        when '"' then encoding.index('"', index + 2) + 1
        when "?" then (encoding[index + 2] == "<") ? balanced(encoding, index + 2) : index + 2
        else index + 1
        end
      end

      private def balanced(encoding, index)
        pairs = { "{" => "}", "(" => ")", "[" => "]", "<" => ">" }
        depth = 0
        (index...(encoding.size)).each do |at|
          depth += 1 if pairs.key?(encoding[at])
          depth -= 1 if pairs.value?(encoding[at])
          return at + 1 if depth.zero?
        end
        raise Error, "#{encoding} is no type encoding"
      end

      private def protocol_types(protocol, sel)
        [true, false].each do |required|
          count = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
          list = Runtime::PROTOCOL_METHODS.call(protocol, required, true, count)
          next if list.null?

          begin
            size = count[0, Fiddle::SIZEOF_INT].unpack1("I")
            size.times do |at|
              name, types = list[at * 2 * Fiddle::SIZEOF_VOIDP, 2 * Fiddle::SIZEOF_VOIDP].unpack("J2")
              return Fiddle::Pointer.new(types).to_s if name == sel
            end
          ensure
            Runtime::FREE.call(list)
          end
        end
        adopted(protocol).each do |parent|
          found = protocol_types(parent, sel)
          return found if found
        end
        nil
      end

      private def adopted(protocol)
        count = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
        list = Runtime::PROTOCOL_PROTOCOLS.call(protocol, count)
        return [] if list.null?

        size = count[0, Fiddle::SIZEOF_INT].unpack1("I")
        list[0, size * Fiddle::SIZEOF_VOIDP].unpack("J*").tap { Runtime::FREE.call(list) }
      end
    end

    # An Objective-C object, or class, as Ruby sees it: each message is a
    # method call (see ObjC). Two stand for the same object when they
    # hold the same pointer.
    class Object
      # Gives an object's reference back on the main queue.
      class Release
        def initialize(address)
          @address = address
        end

        def call(*)
          Runtime::DISPATCH_ASYNC.call(Runtime::MAIN_QUEUE, @address, Runtime::RELEASE)
        end
      end

      class << self
        # The Objective-C class this Ruby class stands for, a pointer,
        # made and registered on first use for a class defined in Ruby.
        def objc_pointer
          objc_define if @ruby_subclass
          @objc_pointer
        end

        # The Objective-C class's name.
        attr_reader :objc_name

        # Whether this class was written in Ruby, with objc_method.
        def defined_in_ruby?
          @defined_in_ruby || false
        end

        # A new object, as Objective-C's <tt>[[Class alloc] init]</tt>.
        def new
          alloc.init
        end

        # Sends a class method: see ObjC.
        def method_missing(name, *arguments, **keywords, &)
          return super if objc_pointer.nil?

          ObjC.send_message(objc_pointer, Object.selector_for(name, arguments, keywords), arguments + keywords.values)
        end

        def respond_to_missing?(name, include_private = false)
          return super if objc_pointer.nil?

          !ObjC.encoding_of(objc_pointer, ObjC.selector(Object.selector_for(name, [nil], {}))).nil? || super
        end

        # The selector a call of +name+ with +arguments+ and +keywords+
        # sends: "name" for none, "name:" for one, and each keyword's
        # part after it; <tt>name=</tt> is <tt>setName:</tt>.
        def selector_for(name, arguments, keywords)
          base = name.to_s
          base = "set#{base[0].upcase}#{base[1..-2]}" if base.end_with?("=")
          raise ArgumentError, "#{name} takes at most one argument before its keywords" if arguments.size > 1
          return base if arguments.empty? && keywords.empty?

          "#{base}:#{keywords.keys.map { |key| "#{key}:" }.join}"
        end

        # Declares the protocols this class, defined in Ruby, conforms
        # to, whose methods' encodings its objc_method methods take.
        #
        # +objc_getProtocol+ finds only a protocol that compiled code in
        # the process refers to, and UIKit's own are not always one. For
        # a protocol in PROTOCOL_ENCODINGS that it does not find, the
        # class conforms by answering the protocol's selectors, which is
        # all UIKit asks of a delegate or a data source
        # (+respondsToSelector:+), and the encodings are the table's.
        def objc_protocols(*names)
          objc_define
          @protocols = protocols + names.map(&:to_s)
          names.each do |name|
            protocol = Runtime::GET_PROTOCOL.call(name.to_s)
            if protocol.null?
              raise Error, "Objective-C has no protocol #{name}" unless PROTOCOL_ENCODINGS.key?(name.to_s)

              next
            end

            Runtime::ADD_PROTOCOL.call(objc_pointer, protocol)
          end
          self
        end

        # Gives Objective-C a method of this class's instances.
        #
        # With a block, +name+ is the selector, spelled as Apple
        # documents it, and the block is the method, with an argument for
        # each part, as UITableViewDataSource's methods, which all begin
        # with tableView, need:
        #
        #   objc_method("tableView:numberOfRowsInSection:") { |table, section| items.size }
        #
        # Without one, +name+ is a Ruby method of the class whose
        # parameters spell its selector: the first part from the name and
        # one more part for each keyword, as a message from Ruby does
        # (<tt>def add(number, to:)</tt> is <tt>add:to:</tt>).
        #
        # Its encoding is +types+, or else the one a protocol of
        # objc_protocols or the superclass gives the selector, or else
        # an object for each argument and no result. Returns the Ruby
        # method's name.
        def objc_method(name, types = nil, &body)
          objc_define
          return objc_block_method(name.to_s, types, &body) if body

          parameters = instance_method(name).parameters
          keywords = parameters.select { |kind, _| %i[key keyreq].include?(kind) }.map(&:last)
          positional = parameters.count { |kind, _| %i[req opt].include?(kind) }
          selector = selector_for(name, Array.new(positional), keywords.to_h { |key| [key, nil] })
          types ||= ObjC.protocol_encoding(protocols, selector) || inherited_encoding(selector) ||
            "v@:#{'@' * (positional + keywords.size)}"
          add_method(selector, types) do |object, values|
            object.public_send(name, *values.first(positional), **keywords.zip(values.drop(positional)).to_h)
          end
          name
        end

        # The protocols this class, or a Ruby class it inherits from, conforms to.
        def protocols
          inherited = superclass.respond_to?(:protocols) ? superclass.protocols : []
          inherited + (@protocols || [])
        end

        private def objc_block_method(selector, types, &body)
          define_method(selector, &body)
          types ||= ObjC.protocol_encoding(protocols, selector) || inherited_encoding(selector) ||
            "v@:#{'@' * selector.count(':')}"
          add_method(selector, types) { |object, values| object.public_send(selector, *values) }
          selector.to_sym
        end

        private def objc_bind(pointer, name)
          @objc_pointer = pointer
          @objc_name = name
        end

        # A named subclass is one an app defines; ObjC.ruby_class makes
        # its own anonymous and binds them itself.
        private def inherited(subclass)
          super
          subclass.instance_variable_set(:@ruby_subclass, true) if subclass.name
        end

        private def objc_define
          return if defined_in_ruby?

          parent = superclass
          raise Error, "#{self} inherits from no Objective-C class" unless parent.respond_to?(:objc_pointer) && parent.objc_pointer

          name = self.name&.gsub("::", "_") || raise(Error, "an Objective-C class needs a name")
          pointer = Runtime::ALLOCATE_CLASS.call(parent.objc_pointer, name, 0)
          raise Error, "Objective-C has a class #{name} already" if pointer.null?

          Runtime::REGISTER_CLASS.call(pointer)
          objc_bind(pointer.to_i, name)
          @defined_in_ruby = true
          ObjC.register(pointer.to_i, self)
          add_dealloc
        end

        private def inherited_encoding(selector)
          method = Runtime::INSTANCE_METHOD.call(superclass.objc_pointer, ObjC.selector(selector))
          method.null? ? nil : Runtime::METHOD_TYPES.call(method).to_s
        end

        private def add_method(selector, types, &body)
          returns, _receiver, _command, *parameters = ObjC.parse(types)
          zero = %w[@ # : * ^].include?(returns[0]) ? 0 : (%w[d f].include?(returns[0]) ? 0.0 : 0)
          closure = Fiddle::Closure::BlockCaller.new(ObjC.fiddle_type(returns),
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, *parameters.map { |type| ObjC.fiddle_type(type) }]) do |receiver, _sel, *values|
            Object.dispatch(receiver, returns, zero) do |object|
              body.call(object, parameters.zip(values).map { |type, value| ObjC.from_c(type, value) })
            end
          end
          ObjC.keep(closure)
          Runtime::ADD_METHOD.call(objc_pointer, ObjC.selector(selector), closure, types)
        end

        private def add_dealloc
          parent = superclass.objc_pointer
          send_super = Fiddle::Function.new(Runtime::MSG_SEND_SUPER, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          dealloc = ObjC.selector("dealloc")
          closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |receiver, _sel|
            ObjC.forget(receiver.to_i)
            sup = [receiver.to_i, parent].pack("J2")
            send_super.call(Fiddle::Pointer[sup], dealloc)
          end
          ObjC.keep(closure)
          Runtime::ADD_METHOD.call(objc_pointer, dealloc, closure, "v@:")
        end
      end

      # Runs +block+ with the Ruby object for +receiver+, and converts its
      # result to +returns+. An exception would unwind through UIKit's
      # frames, which Ruby must never do, so it is printed, as Ruby
      # prints one its program does not rescue, and the method returns
      # +zero+; SystemExit ends the process with its status.
      def self.dispatch(receiver, returns, zero)
        result = yield(ObjC.wrap(receiver))
        (returns[0] == "v") ? nil : ObjC.to_c(returns, result)
      rescue SystemExit => e
        $stdout.flush
        $stderr.flush
        Kernel.exit!(e.status)
      rescue Exception => e
        warn(e.full_message(highlight: false))
        zero
      end

      # The pointer to the Objective-C object.
      attr_reader :objc_pointer

      # The integer value of the pointer, so Fiddle passes the object.
      def to_i
        objc_pointer
      end

      # Sends a message: see ObjC.
      def method_missing(name, *arguments, **keywords, &)
        objc_send(Object.selector_for(name, arguments, keywords), *arguments, *keywords.values)
      end

      def respond_to_missing?(name, include_private = false)
        selector = Object.selector_for(name, [], {})
        !ObjC.encoding_of(objc_pointer, ObjC.selector(selector)).nil? ||
          !ObjC.encoding_of(objc_pointer, ObjC.selector("#{selector}:")).nil? || super
      end

      # Sends the message +selector+, spelled in full, such as
      # <tt>"setTitle:forState:"</tt>, for a name Ruby's own methods take.
      # An init method consumes the reference this object held.
      def objc_send(selector, *arguments)
        ObjC.send_message(objc_pointer, selector, arguments).tap { disown if ObjC.init?(selector) }
      end

      # The text of an NSString, or else the object's description.
      def to_s
        string = ObjC.class_named("NSString")
        text = isKindOfClass(string) ? self : description
        text.objc_send("UTF8String").to_s.force_encoding(Encoding::UTF_8)
      end

      def inspect
        "#<#{self.class.objc_name || self.class.name} 0x#{objc_pointer.to_s(16)}>"
      end

      def ==(other)
        other.respond_to?(:objc_pointer) && other.objc_pointer == objc_pointer
      end
      alias eql? ==

      def hash
        objc_pointer.hash
      end

      private def objc_hold(address, held: true)
        @objc_pointer = address
        ObjectSpace.define_finalizer(self, Release.new(address)) if held
      end

      private def disown
        ObjectSpace.undefine_finalizer(self)
      end
    end

    # UIKit, whose classes Ruby names before any code of the app does.
    load_framework("UIKit")
  end
end
