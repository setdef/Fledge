# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"

module Basket
  # Ruby's way to the Objective-C runtime, and through it to UIKit and
  # AppKit, with nothing but Fiddle, which Ruby bundles. It is only as
  # much as Basket needs, and it runs under any Ruby on a computer that
  # has the Objective-C runtime and the frameworks it is asked for:
  # Foundation and AppKit on a Mac, and UIKit on an iPhone or iPad.
  #
  # An Objective-C message is a method call whose name is the selector's
  # first part and whose keywords are the rest; <tt>name=</tt> sends
  # <tt>setName:</tt>:
  #
  #   table.dequeueReusableCellWithIdentifier("item", forIndexPath: path)
  #   label.text = "Hello"
  #
  # A class of UIKit's is a constant here, and a Ruby class that inherits
  # from one is an Objective-C class of that name, whose methods defined
  # with +objc_method+ Objective-C can send:
  #
  #   class SceneDelegate < Basket::ObjC::UIResponder
  #     objc_protocols "UIWindowSceneDelegate"
  #
  #     objc_method("scene:willConnectToSession:options:") do |scene, session, options|
  #       ...
  #     end
  #   end
  #
  # How it works is what the Objective-C runtime's C functions
  # (<tt>objc_msgSend</tt> and its neighbors) say, called through Fiddle:
  # a message looks up the receiver's method, reads its type encoding,
  # and calls <tt>objc_msgSend</tt> with the types the encoding gives;
  # a method written in Ruby is a Fiddle::Closure that
  # <tt>class_addMethod</tt> gives a class made with
  # <tt>objc_allocateClassPair</tt>.
  #
  # UIKit's and AppKit's objects are the main thread's to use, so a
  # program that draws its screen runs its Ruby there and hands the
  # thread to UIKit with ObjC.application_main, or to AppKit by sending
  # NSApplication +run+.
  #
  # A struct that a method takes by value, such as an NSRect or an
  # NSEdgeInsets, is an Array of its numbers, nested as the struct is:
  #
  #   stack.edgeInsets = [20.0, 20.0, 20.0, 20.0]
  #   window.setContentSize([480.0, 360.0])
  #
  # On 64-bit ARM, which is every Mac and iPhone Fledge builds for, a
  # struct of up to four doubles travels as that many doubles, so it is
  # passed as that many arguments. A struct a method returns cannot come
  # back: Fiddle returns one register.
  module ObjC
    # libobjc, which every process of Apple's systems links through
    # Foundation.
    LIBRARY = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")

    # Raised for what the bridge cannot do: a protocol it has no
    # encodings for, or a type in an encoding Fiddle cannot pass.
    class Error < StandardError; end

    # The C functions the bridge calls, from libobjc and libdispatch.
    module Runtime
      # A pointer, in Fiddle's type codes.
      P = Fiddle::TYPE_VOIDP
      # A BOOL.
      B = Fiddle::TYPE_BOOL

      # The C function +name+ of +handle+, which Ruby calls holding its
      # lock, since what it runs may call Ruby back.
      def self.function(name, args, ret, handle = LIBRARY)
        Fiddle::Function.new(handle[name], args, ret, need_gvl: true)
      end

      # The class of a name.
      GET_CLASS = function("objc_getClass", [P], P)
      # The protocol of a name, which only compiled code makes known.
      GET_PROTOCOL = function("objc_getProtocol", [P], P)
      # The selector of a name.
      REGISTER_NAME = function("sel_registerName", [P], P)
      # An object's class.
      OBJECT_CLASS = function("object_getClass", [P], P)
      # A class's name.
      CLASS_NAME = function("class_getName", [P], P)
      # A class's superclass.
      SUPERCLASS = function("class_getSuperclass", [P], P)
      # Whether a class is a metaclass.
      META_CLASS = function("class_isMetaClass", [P], B)
      # A class's instance method of a selector.
      INSTANCE_METHOD = function("class_getInstanceMethod", [P, P], P)
      # A method's type encoding.
      METHOD_TYPES = function("method_getTypeEncoding", [P], P)
      # A new class, not yet registered.
      ALLOCATE_CLASS = function("objc_allocateClassPair", [P, P, Fiddle::TYPE_SIZE_T], P)
      # Registers a class made with ALLOCATE_CLASS.
      REGISTER_CLASS = function("objc_registerClassPair", [P], Fiddle::TYPE_VOID)
      # Gives a class a method, whose implementation is a Fiddle::Closure.
      ADD_METHOD = function("class_addMethod", [P, P, P, P], B)
      # Declares that a class adopts a protocol.
      ADD_PROTOCOL = function("class_addProtocol", [P, P], B)
      # Takes a reference to an object.
      RETAIN = function("objc_retain", [P], P)

      # objc_msgSend, whose C signature differs for each method.
      MSG_SEND = LIBRARY["objc_msgSend"]
      # objc_msgSendSuper, for a Ruby class's dealloc.
      MSG_SEND_SUPER = LIBRARY["objc_msgSendSuper"]
      # objc_release, which the main queue calls for an object Ruby let go.
      RELEASE = LIBRARY["objc_release"]
      # The main queue, which dispatch_get_main_queue() returns.
      MAIN_QUEUE = Fiddle::Handle::DEFAULT["_dispatch_main_q"]
      # Calls a function on a queue, later.
      DISPATCH_ASYNC = function("dispatch_async_f", [P, P, P], Fiddle::TYPE_VOID, Fiddle::Handle::DEFAULT)
    end
    private_constant :Runtime

    # The Fiddle type for each type code of an encoding Fiddle can pass
    # (Apple's "Type Encodings"), where +l+ and +L+ are 32 bits on every
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
    # rules for automatic reference counting.
    OWNING_FAMILIES = %w[alloc new copy mutableCopy init].freeze

    # The type encodings of the methods of the UIKit and AppKit protocols
    # a Ruby class here implements, from their headers, for 64-bit ARM:
    # +q+ is NSInteger, +B+ is BOOL. +objc_getProtocol+ finds only a
    # protocol that compiled code in the process refers to, and a program
    # of Ruby alone has none of UIKit's. UIKit and AppKit ask a delegate
    # or a data source +respondsToSelector:+, so a class that answers a
    # protocol's selectors with these encodings serves without declaring
    # it.
    PROTOCOL_ENCODINGS = {
      "UITableViewDataSource" => {
        "tableView:numberOfRowsInSection:" => "q32@0:8@16q24",
        "tableView:cellForRowAtIndexPath:" => "@32@0:8@16@24",
        "tableView:commitEditingStyle:forRowAtIndexPath:" => "v40@0:8@16q24@32",
      },
      "UIApplicationDelegate" => {
        "application:didFinishLaunchingWithOptions:" => "B32@0:8@16@24",
      },
      "UIWindowSceneDelegate" => {
        "scene:willConnectToSession:options:" => "v40@0:8@16@24@32",
      },
      "NSApplicationDelegate" => {
        "applicationDidFinishLaunching:" => "v24@0:8@16",
        "applicationShouldTerminateAfterLastWindowClosed:" => "B24@0:8@16",
      },
      "NSTableViewDataSource" => {
        "numberOfRowsInTableView:" => "q24@0:8@16",
      },
      "NSTableViewDelegate" => {
        "tableView:viewForTableColumn:row:" => "@40@0:8@16@24q32",
      },
      "NSMenuItemValidation" => {
        "validateMenuItem:" => "B24@0:8@16",
      },
    }.freeze

    @functions = {} # the objc_msgSend of each signature
    @classes = {} # the Ruby class of each Objective-C class, by pointer
    @instances = {} # each live instance of a class defined in Ruby, by pointer
    @closures = [] # each method a Ruby class gave Objective-C, kept from the collector

    class << self
      # Loads the framework +name+ into the process, as dlopen does the
      # file of its path in the system's Frameworks folder, which defines
      # its classes for the Objective-C runtime: a process whose code
      # refers to none of UIKit's classes does not have it loaded. Returns whether
      # the framework loaded, which is how a program asks whether it is
      # on a system that has it.
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
      # the scene delegate Info.plist lists. Returns only if UIKit does,
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
      # returned object then holds; otherwise it takes one for itself.
      # Each holds its reference until Ruby collects it, then gives it
      # back on the main queue, where UIKit needs its objects released.
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
        returns, _receiver, _command, *parameters = parse(encoding)
        raise ArgumentError, "#{selector} takes #{parameters.size} arguments, not #{arguments.size}" unless parameters.size == arguments.size

        kept = [] # the objects made for the arguments, alive until the call returns
        types = []
        values = []
        parameters.zip(arguments).each do |type, value|
          if type.start_with?("{")
            numbers = struct_numbers(type, value)
            types.concat(["d"] * numbers.size)
            values.concat(numbers)
          else
            types << type
            values << to_c(type, value, kept)
          end
        end
        result = function(returns, types).call(receiver, sel, *values)
        kept.clear
        from_c(returns, result, owned: owning?(selector))
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

      # The doubles of the struct +value+, an Array nested as the struct
      # of encoding +type+ is: its fields, in order, as Floats. Raises
      # an Error for a struct of anything but up to four doubles, which
      # 64-bit ARM passes as that many doubles.
      def struct_numbers(type, value)
        fields = struct_fields(type)
        raise Error, "Fiddle cannot pass an argument of type #{type}" unless fields.size.between?(1, 4) && fields.all?("d")

        numbers = Array(value).flatten
        raise ArgumentError, "#{type} takes #{fields.size} numbers, not #{numbers.size}" unless numbers.size == fields.size

        numbers.map { |number| Float(number) }
      end

      # The type codes of the fields of the struct of encoding +type+,
      # with the fields of its own structs in place of them.
      def struct_fields(type)
        return [type] unless type.start_with?("{")

        parse(type[(type.index("=") + 1)...-1]).flat_map { |field| struct_fields(field) }
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
        when "*" then value.to_i.zero? ? nil : Fiddle::Pointer.new(value.to_i).to_s
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

      # The encoding of the instance method +selector+ in the first of
      # +protocols+, UIKit's and AppKit's protocols by name, that PROTOCOL_ENCODINGS
      # has it for, or nil.
      def protocol_encoding(protocols, selector)
        protocols.each do |name|
          found = PROTOCOL_ENCODINGS.dig(name.to_s, selector.to_s)
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

      # Whether the caller owns what +selector+ returns.
      def owning?(selector)
        OWNING_FAMILIES.any? { |family| family?(selector, family) }
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
        else index + 1
        end
      end

      private def skip_object(encoding, index)
        case encoding[index + 1]
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
    end

    # An Objective-C object, or class, as Ruby sees it: each message is a
    # method call (see ObjC).
    class Object
      # Gives an object's reference back on the main queue.
      class Release
        # A release of the object at +address+, which Ruby's collector calls
        # as an object's finalizer.
        def initialize(address)
          @address = address
        end

        # Gives the reference back.
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

        # Declares the UIKit or AppKit protocols this class, defined in Ruby,
        # conforms to, whose methods' encodings its objc_method methods
        # take (PROTOCOL_ENCODINGS). When the Objective-C runtime has the
        # protocol, the class adopts it too.
        def objc_protocols(*names)
          objc_define
          names.each do |name|
            raise Error, "Basket::ObjC has no encodings for the protocol #{name}" unless PROTOCOL_ENCODINGS.key?(name.to_s)

            @protocols = protocols + [name.to_s]
            protocol = Runtime::GET_PROTOCOL.call(name.to_s)
            Runtime::ADD_PROTOCOL.call(objc_pointer, protocol) unless protocol.null?
          end
          self
        end

        # Gives Objective-C a method of this class's instances: +selector+
        # is spelled as Apple documents it, and the block is the method,
        # with an argument for each part:
        #
        #   objc_method("tableView:numberOfRowsInSection:") { |table, section| items.size }
        #
        # Its encoding is +types+, or else the one a protocol of
        # objc_protocols gives the selector. Returns the Ruby method's
        # name.
        def objc_method(selector, types = nil, &body)
          objc_define
          define_method(selector, &body)
          types ||= ObjC.protocol_encoding(protocols, selector) ||
            raise(Error, "no protocol of #{name} gives #{selector} an encoding")
          add_method(selector, types) { |object, values| object.public_send(selector, *values) }
          selector.to_sym
        end

        # The protocols this class conforms to.
        def protocols
          @protocols || []
        end

        private def objc_bind(pointer, name)
          @objc_pointer = pointer
          @objc_name = name
        end

        # A named subclass is one an app defines; ObjC.ruby_class makes
        # anonymous classes and binds them itself.
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

        private def add_method(selector, types, &body)
          returns, _receiver, _command, *parameters = ObjC.parse(types)
          closure = Fiddle::Closure::BlockCaller.new(ObjC.fiddle_type(returns),
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, *parameters.map { |type| ObjC.fiddle_type(type) }]) do |receiver, _sel, *values|
            Object.dispatch(receiver, returns) do |object|
              body.call(object, parameters.zip(values).map { |type, value| ObjC.from_c(type, value) })
            end
          end
          ObjC.keep(closure)
          Runtime::ADD_METHOD.call(objc_pointer, ObjC.selector(selector), closure, types)
        end

        # Gives the class a dealloc that forgets the Ruby object for the
        # instance, so that no later object at its address is taken for
        # it, and then calls its superclass's.
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
      # zero; SystemExit ends the process with its status.
      def self.dispatch(receiver, returns)
        result = yield(ObjC.wrap(receiver))
        (returns[0] == "v") ? nil : ObjC.to_c(returns, result)
      rescue SystemExit => e
        $stdout.flush
        $stderr.flush
        Kernel.exit!(e.status)
      rescue Exception => e
        warn(e.full_message(highlight: false))
        %w[d f].include?(returns[0]) ? 0.0 : 0
      end

      # The pointer to the Objective-C object.
      attr_reader :objc_pointer

      # Sends a message: see ObjC.
      def method_missing(name, *arguments, **keywords, &)
        objc_send(Object.selector_for(name, arguments, keywords), *arguments, *keywords.values)
      end

      # Sends the message +selector+, spelled in full, such as
      # <tt>"setTitle:forState:"</tt>, for a name that Ruby methods take.
      # An init method consumes the reference this object held.
      def objc_send(selector, *arguments)
        ObjC.send_message(objc_pointer, selector, arguments).tap { disown if ObjC.init?(selector) }
      end

      # The objects of an NSArray, as a Ruby Array.
      def to_a
        Array.new(count) { |index| objectAtIndex(index) }
      end

      # The text of an NSString, or else the object's description.
      def to_s
        string = ObjC.class_named("NSString")
        text = isKindOfClass(string) ? self : description
        text.objc_send("UTF8String").to_s.force_encoding(Encoding::UTF_8)
      end

      private def objc_hold(address, held: true)
        @objc_pointer = address
        ObjectSpace.define_finalizer(self, Release.new(address)) if held
      end

      private def disown
        ObjectSpace.undefine_finalizer(self)
      end
    end
  end
end
