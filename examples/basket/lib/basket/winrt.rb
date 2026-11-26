# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"

module Basket
  # Ruby's way to WinUI 3, the Windows App SDK's controls, with nothing
  # but Fiddle, which Ruby bundles. WinUI is a WinRT API: a program gets
  # a class from combase.dll, and calls an object's methods by their
  # place in its interface's table of functions, which Microsoft's
  # .winmd files list in order. It is only as much as Basket's screen
  # calls, and it runs under any Ruby on a Windows that has the Windows
  # App Runtime, which Windows registers for each person who installs it
  # (from the Microsoft Store, or with its installer):
  #
  #   WinRT.available? # => true
  #   WinRT.start do
  #     window = WinRT.activate("Microsoft.UI.Xaml.Window").qi(IID_WINDOW)
  #     window.hr(26, [], what: "Activate")
  #   end
  #
  # +start+ gives the calling thread to WinUI, which calls the block on
  # it, as it calls an app written in C#, and WinUI's events call Ruby
  # on that thread too, with the lock Ruby holds, so Thread.main is the
  # thread that makes the controls. A WinRT call that finishes on another
  # thread would end the process, since Ruby does not know that thread.
  # The one exception is each object's AddRef and Release, which are
  # native code, since Windows may call them on a thread it made when
  # the process ends (see Implementation).
  module WinRT
    # What WinRT's functions take and give, in Fiddle's type codes.
    # A pointer.
    POINTER = Fiddle::TYPE_VOIDP
    # An int.
    INT = Fiddle::TYPE_INT
    # A UINT.
    UINT = -Fiddle::TYPE_INT
    # A 64-bit integer, which a function takes where C has a struct of 8 bytes.
    INT64 = Fiddle::TYPE_LONG_LONG

    # The Windows App Runtime's framework package, which Microsoft
    # publishes for every release of its major version 2, and the least
    # version of it whose interfaces this bridge calls.
    FRAMEWORK = "Microsoft.WindowsAppRuntime.2_8wekyb3d8bbwe"
    # Version 2.7.0.0, as a PACKAGE_VERSION holds it: four 16-bit numbers.
    FRAMEWORK_VERSION = (2 << 48) | (7 << 32)
    # PackageDependencyProcessorArchitectures_X64 and _Arm64.
    X64 = 4
    # Windows on ARM's.
    ARM64 = 0x10
    # S_OK's opposite: an HRESULT is a failure when its high bit is set.
    FAILED = 0x80000000
    # E_NOINTERFACE
    NO_INTERFACE = -2147467262

    # The WinRT interfaces the bridge itself calls, by IID.
    IID_UNKNOWN = "00000000-0000-0000-c000-000000000046"
    # IInspectable, which every WinRT object answers.
    IID_INSPECTABLE = "af86e2e0-b12d-4c6a-9c5a-d7aa65101e90"
    # Application's static methods: Current 6, Start 7.
    IID_APPLICATION_STATICS = "4e0d09f5-4358-512c-a987-503b52848e95"
    # Application's constructor: CreateInstance 6.
    IID_APPLICATION_FACTORY = "9fd96657-5294-5a65-a1db-4fea143597da"
    # What an Application subclass overrides: OnLaunched 6.
    IID_APPLICATION_OVERRIDES = "a33e81ef-c665-503b-8827-d27ef1720a06"
    # An Application: put_Resources 7, Exit 17.
    IID_APPLICATION = "06a8f4e7-1146-55af-820d-ebd55643b021"
    # The callback Application.Start takes, a delegate.
    IID_INIT_CALLBACK = "d8eef1c9-1234-56f1-9963-45dd9c80a661"
    # What an Application answers for WinUI to find controls outside
    # Microsoft.UI.Xaml.dll: GetXamlType 6 and 7, GetXmlnsDefinitions 8.
    IID_METADATA_PROVIDER = "a96251f0-2214-5d53-8746-ce99a2593cd7"
    # A ResourceDictionary.
    IID_RESOURCE_DICTIONARY = "1b690975-a710-5783-a6e1-15836f6186c2"
    # PropertyValue's static methods: CreateString 18.
    IID_PROPERTY_VALUE_STATICS = "629bdbc8-d932-4ff4-96b9-8d96c5c1e858"
    # A boxed value as a string: GetString 19.
    IID_PROPERTY_VALUE = "4bd682dd-7554-40e9-9a9b-82654ede7e62"

    # Raised when a call to Windows fails.
    class Error < StandardError; end

    # Windows' C functions, and WinRT's strings and errors.
    module Win
      @functions = {}

      # The C function +name+ of the library +file+.
      def self.function(file, name, args, ret)
        @functions[[file, name]] ||= Fiddle::Function.new(Fiddle::Handle.new(file)[name], args, ret)
      end

      # The address of the C function +name+ of the library +file+.
      def self.address(file, name)
        Fiddle::Handle.new(file)[name]
      end

      # A buffer of +size+ zeroed bytes, which Ruby frees.
      def self.buffer(size)
        Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE).tap { |pointer| pointer[0, size] = "\0".b * size }
      end

      # +text+ as the zero-ended UTF-16 a wide function takes.
      def self.wide(text)
        bytes = "#{text}\0".encode(Encoding::UTF_16LE).b
        buffer(bytes.bytesize).tap { |pointer| pointer[0, bytes.bytesize] = bytes }
      end

      # A GUID's 16 bytes, as Windows lays them out: three little-endian
      # fields, then eight bytes.
      def self.guid(text)
        a, b, c, d, e = text.split("-")
        [a.hex, b.hex, c.hex].pack("Vvv") + [d + e].pack("H*")
      end

      # A pointer to the GUID +text+.
      def self.iid(text)
        buffer(16).tap { |pointer| pointer[0, 16] = guid(text) }
      end

      # +hr+, an HRESULT, unless it is a failure, which raises Error.
      def self.check(hr, what)
        hr &= 0xffffffff
        raise Error, "#{what} failed: 0x#{hr.to_s(16)}" if hr >= FAILED

        hr
      end

      # +text+ as an HSTRING, WinRT's string, which the callee copies.
      def self.hstring(text)
        out = buffer(8)
        function("combase.dll", "WindowsCreateString", [POINTER, UINT, POINTER], INT).call(wide(text), text.encode(Encoding::UTF_16LE).bytesize / 2, out)
        out[0, 8].unpack1("Q")
      end

      # The String of an HSTRING.
      def self.string(handle)
        return "" if handle.zero?

        length = buffer(4)
        raw = function("combase.dll", "WindowsGetStringRawBuffer", [POINTER, POINTER], POINTER).call(handle, length).to_i
        Fiddle::Pointer.new(raw)[0, length[0, 4].unpack1("L") * 2].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
      end
    end

    # A WinRT object made elsewhere, called through its vtable by slot
    # number: 0 to 2 are IUnknown's, 3 to 5 IInspectable's, and the
    # interface's methods follow, in the order its .winmd lists them.
    class Interface
      # Each function called, by its address and its argument types.
      CALLS = {}

      # The address of the object.
      attr_reader :ptr

      # The object at +ptr+.
      def initialize(ptr)
        @ptr = ptr
      end

      # Calls the method at +index+ with +args+ of +types+, and returns
      # its HRESULT.
      def call(index, types = [], *)
        vtable = Fiddle::Pointer.new(@ptr)[0, 8].unpack1("Q")
        address = Fiddle::Pointer.new(vtable + (index * 8))[0, 8].unpack1("Q")
        (CALLS[[address, types]] ||= Fiddle::Function.new(address, [POINTER, *types], INT)).call(@ptr, *)
      end

      # Calls a method that returns an HRESULT, and raises Error on a failure.
      def hr(index, types = [], *, what: "slot #{index}")
        Win.check(call(index, types, *), what)
      end

      # Calls a method whose last argument is where it writes its result,
      # and returns the 64 bits it wrote.
      def out(index, types = [], *, what: "slot #{index}")
        cell = Win.buffer(8)
        hr(index, [*types, POINTER], *, cell, what:)
        cell[0, 8].unpack1("Q")
      end

      # Like +out+, for a result that is an object: an Interface, or nil.
      def out_object(index, types = [], *, what: "slot #{index}")
        pointer = out(index, types, *, what:)
        Interface.new(pointer) unless pointer.zero?
      end

      # Like +out+, for a result that is a 32-bit integer, signed.
      def out_int(index, what: "slot #{index}")
        value = out(index, what:) & 0xffffffff
        (value >= 0x80000000) ? value - 0x100000000 : value
      end

      # Like +out+, for a result that is a string.
      def out_string(index, what: "slot #{index}")
        Win.string(out(index, what:))
      end

      # The same object as the interface of +iid+, or nil when it has none.
      def qi(iid)
        cell = Win.buffer(8)
        return if (call(0, [POINTER, POINTER], Win.iid(iid), cell) & 0xffffffff) >= FAILED

        Interface.new(cell[0, 8].unpack1("Q"))
      end
    end

    # A COM object implemented in Ruby, for WinUI to call. Each interface
    # is 16 bytes of memory that start with a pointer to a table of
    # Fiddle::Closure, except for AddRef and Release, which hold native
    # code. +interfaces+ maps an IID to its methods after
    # IUnknown's and IInspectable's, each [argument types, block]. A
    # delegate (an event handler) has IUnknown's methods and Invoke.
    class Implementation
      # What WinUI may call for as long as the process lives: the memory of
      # each object, and its closures.
      KEEP = []

      # The address of the object's IUnknown.
      attr_reader :ptr

      # The object an aggregating object hands the interfaces it does
      # not answer to.
      attr_writer :inner

      # The object named +name+ that answers +interfaces+.
      def initialize(name, interfaces, delegate: false)
        @name = name
        @inner = nil
        @blocks = {}
        base = base_closures(inspectable: !delegate)
        interfaces.each do |iid, methods|
          closures = base + methods.map { |args, body| closure([POINTER, *args]) { |*values| guarded(body, values) } }
          @blocks[Win.guid(iid)] = block_of(closures)
        end
        identity = delegate ? @blocks.values.first : block_of(base)
        @blocks[Win.guid(IID_UNKNOWN)] = identity
        @blocks[Win.guid(IID_INSPECTABLE)] = identity unless delegate
        @ptr = identity.to_i
        KEEP << self
      end

      private def closure(args, &)
        Fiddle::Closure::BlockCaller.new(INT, args, &)
      end

      private def block_of(closures)
        vtable = Fiddle::Pointer.malloc(8 * closures.size)
        closures.each_with_index { |function, i| vtable[i * 8, 8] = [function.to_i].pack("Q") }
        block = Fiddle::Pointer.malloc(16)
        block[0, 8] = [vtable.to_i].pack("Q")
        KEEP << vtable << block << closures
        block
      end

      # A Ruby exception cannot unwind through WinUI's frames, and WinUI
      # ends the process for a handler that fails, so the exception is
      # printed and the handler reports success.
      private def guarded(body, values)
        body.call(*values)
      rescue Exception => e
        warn "Basket: #{e.class}: #{e.message}", *e.backtrace.first(6)
        0
      end

      # IUnknown's three methods, and IInspectable's three, which tell
      # WinRT nothing about the object but its name.
      #
      # AddRef and Release hold the address of kernel32's
      # GetCurrentThreadId, not a closure. At process exit, Windows may
      # release a COM object on a thread it made, and a closure that
      # runs there asks Ruby for its lock from a thread Ruby did not make,
      # which ends the process with "[BUG] rb_thread_call_with_gvl() is
      # called by non-ruby thread". Microsoft's documentation says of what
      # each returns, "This value is intended to be used only for test
      # purposes" (IUnknown::AddRef and IUnknown::Release), and KEEP holds
      # every object for the life of the process, so no count frees
      # anything. GetCurrentThreadId, on x64 and on ARM64, ignores the
      # registers that hold its arguments, returns a nonzero value, and
      # calls no Ruby.
      private def base_closures(inspectable:)
        count = Win.address("kernel32.dll", "GetCurrentThreadId")
        list = [
          closure([POINTER, POINTER, POINTER]) { |_this, riid, ppv| query(riid, ppv) },
          count,
          count,
        ]
        return list unless inspectable

        list + [
          closure([POINTER, POINTER, POINTER]) { |_this, count, iids| write(count, [0].pack("L")) && write(iids, [0].pack("Q")) && 0 },
          closure([POINTER, POINTER]) { |_this, out| write(out, [Win.hstring(@name)].pack("Q")) && 0 },
          closure([POINTER, POINTER]) { |_this, out| write(out, [0].pack("L")) && 0 },
        ]
      end

      private def write(address, bytes)
        Fiddle::Pointer.new(address.to_i)[0, bytes.bytesize] = bytes
      end

      # Answers the interfaces the object has, and hands the rest to the
      # inner object of an aggregation, when there is one.
      private def query(riid, ppv)
        block = @blocks[Fiddle::Pointer.new(riid.to_i)[0, 16]]
        if block
          write(ppv, [block.to_i].pack("Q"))
          return 0
        end
        return @inner.call(0, [POINTER, POINTER], riid, ppv) if @inner

        write(ppv, [0].pack("Q"))
        NO_INTERFACE
      end
    end

    # A WinRT delegate of the interface +iid+, which runs +body+ with the
    # arguments WinUI calls it with after the sender.
    def self.delegate(iid, args = [POINTER, POINTER], &body)
      invoke = lambda do |_this, *values|
        body.call(*values)
        0
      end
      Implementation.new("delegate", { iid => [[args, invoke]] }, delegate: true)
    end

    # The static or factory interface +iid+ of the class +name+.
    def self.factory(name, iid)
      cell = Win.buffer(8)
      Win.check(Win.function("combase.dll", "RoGetActivationFactory", [POINTER, POINTER, POINTER], INT).call(Win.hstring(name), Win.iid(iid), cell), "RoGetActivationFactory #{name}")
      Interface.new(cell[0, 8].unpack1("Q"))
    end

    # A new object of the class +name+, made with its default constructor.
    def self.activate(name)
      cell = Win.buffer(8)
      Win.check(Win.function("combase.dll", "RoActivateInstance", [POINTER, POINTER], INT).call(Win.hstring(name), cell), "RoActivateInstance #{name}")
      Interface.new(cell[0, 8].unpack1("Q"))
    end

    # Makes +handler+ the one that runs when +slot+ of +interface+, an
    # add_ method of an event, is raised, and returns it.
    def self.subscribe(interface, slot, handler_iid, &body)
      delegate(handler_iid, &body).tap do |handler|
        interface.hr(slot, [POINTER, POINTER], handler.ptr, Win.buffer(8), what: "add_ event at #{slot}")
      end
    end

    # +text+ as the object a ListView or a Button takes for a string.
    def self.box(text)
      factory("Windows.Foundation.PropertyValue", IID_PROPERTY_VALUE_STATICS).out(18, [POINTER], Win.hstring(text), what: "CreateString")
    end

    # Whether WinUI's classes can be made in this process: they can when
    # the process has the Windows App Runtime's framework package in its
    # package graph, as a packaged app has, or when Windows will add it,
    # as the Windows App SDK's bootstrapper asks Windows to for an app
    # that is not packaged. Windows adds it only when the person has the
    # framework package registered.
    def self.available?
      @available = framework_active? || (add_framework && framework_active?) if @available.nil?
      @available
    end

    # Whether the class of Application can be made.
    def self.framework_active?
      initialize_runtime
      factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS)
      true
    rescue Error, Fiddle::DLError
      false
    end

    # Makes this thread one that WinRT's calls may be made on, a
    # single-threaded apartment, as a window's thread is.
    def self.initialize_runtime
      Win.check(Win.function("combase.dll", "RoInitialize", [INT], INT).call(0), "RoInitialize")
    end

    # Asks Windows (11 and later) to add the framework package to this
    # process's package graph, for as long as the process lives, which
    # is what the bootstrapper's MddBootstrapInitialize2 does.
    def self.add_framework
      kernel = "kernelbase.dll"
      id = Win.buffer(8)
      architecture = RUBY_PLATFORM.match?(/aarch64|arm64/) ? ARM64 : X64
      create = Win.function(kernel, "TryCreatePackageDependency", [POINTER, POINTER, INT64, INT, INT, POINTER, INT, POINTER], INT)
      add = Win.function(kernel, "AddPackageDependency", [POINTER, INT, INT, POINTER, POINTER], INT)
      # The current person, this package family's least version, any
      # architecture of the process's, for the life of the process.
      return false if (create.call(nil, Win.wide(FRAMEWORK), FRAMEWORK_VERSION, architecture, 0, nil, 0, id) & 0xffffffff) >= FAILED

      (add.call(id[0, 8].unpack1("Q"), 0, 0, Win.buffer(8), Win.buffer(8)) & 0xffffffff) < FAILED
    rescue Fiddle::DLError
      false
    end

    # Gives this thread to WinUI, which calls the block on it once the
    # application has started, with Fluent's styles merged in, and
    # returns when the application exits.
    def self.start(&launched)
      initialize_runtime
      Win.function("user32.dll", "SetProcessDpiAwarenessContext", [INT64], INT).call(-4) # per monitor, version 2
      callback = delegate(IID_INIT_CALLBACK, [POINTER]) do |_params|
        application = make_application(&launched)
        Implementation::KEEP << application
      end
      factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS).hr(7, [POINTER], callback.ptr, what: "Application.Start")
      raise @failure if @failure
    end

    # Ends the application, which makes +start+ return.
    def self.quit
      factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS).out_object(6, what: "Application.Current").qi(IID_APPLICATION).hr(17, what: "Exit")
    end

    # An Application that is a subclass of WinUI's, as WinRT makes one,
    # by aggregation: the outer object answers IApplicationOverrides, so
    # that WinUI calls OnLaunched, and IXamlMetadataProvider, by handing
    # each call to the provider of the controls' types, and hands every
    # other interface to the inner object that WinUI made.
    def self.make_application(&launched)
      provider = nil
      forward = lambda do |slot|
        [
          [POINTER, POINTER],
          lambda do |_this, a, b|
            provider ||= activate("Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider").qi(IID_METADATA_PROVIDER)
            provider.call(slot, [POINTER, POINTER], a, b)
          end,
]
      end
      overrides = {
        IID_APPLICATION_OVERRIDES => [[[POINTER], -> (_this, _args) { on_launched(&launched) }]],
        IID_METADATA_PROVIDER => [forward.call(6), forward.call(7), forward.call(8)],
      }
      outer = Implementation.new("Basket.App", overrides)
      inner = Win.buffer(8)
      Win.check(factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_FACTORY).call(6, [POINTER, POINTER, POINTER], outer.ptr, inner, Win.buffer(8)), "Application.CreateInstance")
      outer.inner = Interface.new(inner[0, 8].unpack1("Q"))
      outer
    end

    # What OnLaunched does: merges Fluent's styles into the application's
    # resources, as a WinUI app's App.xaml does, and calls +launched+.
    def self.on_launched(&launched)
      resources = activate("Microsoft.UI.Xaml.Controls.XamlControlsResources").qi(IID_RESOURCE_DICTIONARY)
      factory("Microsoft.UI.Xaml.Application", IID_APPLICATION_STATICS).out_object(6, what: "Application.Current").qi(IID_APPLICATION).hr(7, [POINTER], resources.ptr, what: "put_Resources")
      launched.call
      0
    rescue => e
      @failure = e
      quit
      0
    end
  end
end
