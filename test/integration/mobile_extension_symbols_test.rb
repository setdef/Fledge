# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "stringio"
require_relative "../support/android"

# Which definition each Android extension built as a file calls, when
# two libraries define one name (doc/contributors/design/phone-projects.md,
# "Each extension file's symbols"). The extensions are built with the
# real Android runtime and the developer's NDK, as fledge build builds
# them, and, where an emulator or device is attached (ANDROID_SERIAL),
# opened there in order as Ruby's dln.c opens an extension, with
# RTLD_LAZY | RTLD_GLOBAL (line 376 at Ruby 4.1.0-preview1), by a
# program that prints what each one's function returns. Without the
# runtime, the NDK, or a device they skip, and fail instead where
# FLEDGE_REQUIRE_ANDROID is set, as in CI's Mobile apps (Android
# emulator) job (AndroidRequired).
class MobileExtensionSymbolsTest < Minitest::Test
  include AndroidRequired

  # The program: HOST LIBRARY FUNCTION ... opens each LIBRARY in turn as
  # dln.c does, and prints FUNCTION and what it returns, a line each,
  # flushed, so that what it printed before a function aborts is kept.
  HOST = <<~C
    #include <dlfcn.h>
    #include <stdio.h>

    int main(int argc, char **argv) {
        for (int i = 1; i + 1 < argc; i += 2) {
            void *library = dlopen(argv[i], RTLD_LAZY | RTLD_GLOBAL);
            if (library == NULL) { fprintf(stderr, "%s\\n", dlerror()); return 1; }
            long (*function)(void) = (long (*)(void))dlsym(library, argv[i + 1]);
            if (function == NULL) { fprintf(stderr, "%s\\n", dlerror()); return 1; }
            printf("%s %ld\\n", argv[i + 1], function());
            fflush(stdout);
        }
        return 0;
    }
  C

  # Builds the static library LIBTWIN, whose fledge_twin returns the
  # number the gem's twin/lib.c gives it, and links it into the
  # extension.
  ARCHIVE = <<~MAKE
    LIBTWIN = $(shell pwd)/libtwin/libtwin.a
    LOCAL_LIBS += "$(LIBTWIN)"
    $(OBJS): $(LIBTWIN)
    $(LIBTWIN):
    \tmkdir -p $(@D) && $$CC -fPIC -c $(srcdir)/twin/lib.c -o $(@D)/lib.o && $${AR:-ar} rcs $@ $(@D)/lib.o
  MAKE

  # The names of the NDK's unwinder, whose static libunwind.a an
  # extension may link, whether or not libc++_shared.so exports them.
  UNWINDER = /\A_Unwind_/

  def setup
    @dir = Fledge::LongPath.of(Dir.mktmpdir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Two extensions each link a static library whose fledge_twin returns
  # its own number, and each calls it. Opened RTLD_GLOBAL, the first
  # does not take the second's call: bionic resolves a library against
  # the global group (the program, LD_PRELOAD, and libraries linked -z
  # global) and then its own breadth-first DT_NEEDED closure, which no
  # other extension is in (linker.cpp, soinfo_do_lookup, at
  # android-8.0.0_r1; linker_namespaces.cpp, get_global_group, at
  # android16-release), where glibc would bind the second to the first.
  def test_two_extensions_that_define_one_name_each_call_their_own
    built = compile(twin("twin_a", 1), twin("twin_b", 2))

    built.targets.each_value do |target|
      target.libraries.each do |library|
        assert_match(/ GLOBAL\s+DEFAULT\s+\d+ fledge_twin$/, dynamic_symbols(target, library.path),
          "#{target.target.name}: #{library.feature} exports what its static library defines, as on a desktop")
      end
    end
    printed = on_device(built, %w[twin_a/twin_a twin_a_value twin_b/twin_b twin_b_value])
    on_the_device(printed, "twin_a_value 1\ntwin_b_value 2\n")
  end

  # A shared library the extension links, which defines fledge_twin too
  # and calls it, is opened for the first time as the extension's own
  # DT_NEEDED, behind the extension in its breadth-first group, and so
  # calls the extension's fledge_twin, as glibc's lookup does on a
  # desktop: Fledge leaves the C libraries an extension links as a
  # desktop's mkmf leaves them.
  def test_a_library_an_extension_links_calls_what_the_extension_exports_as_on_a_desktop
    gem = extconf_gem("twin_dep", <<~RUBY, "twin/lib.c" => "int fledge_twin(void) { return 3; }\n", "twin_dep.c" => <<~C, "lib.mk" => <<~MAKE, "twin/dep.c" => <<~DEP)
      require "mkmf"
      create_makefile("twin_dep/twin_dep")
      File.open("Makefile", "a") { |makefile| makefile.puts "include $(srcdir)/lib.mk" }
    RUBY
      #include <ruby.h>
      int fledge_twin(void);
      long twin_dep_lib(void);
      long twin_dep_own(void) { return fledge_twin(); }
      long twin_dep_through_lib(void) { return twin_dep_lib(); }
      void Init_twin_dep(void) { rb_define_module("TwinDep"); }
    C
      #{ARCHIVE}
      LIBDEP = $(shell pwd)/libdep/libtwin_dep_lib.so
      LOCAL_LIBS += -L$(shell pwd)/libdep -ltwin_dep_lib
      $(OBJS): $(LIBDEP)
      $(LIBDEP):
      \tmkdir -p $(@D) && $$CC -shared -fPIC $(srcdir)/twin/dep.c -o $@
    MAKE
      int fledge_twin(void) { return 4; }
      long twin_dep_lib(void) { return fledge_twin(); }
    DEP

    built = compile(gem)

    printed = on_device(built, %w[twin_dep/twin_dep twin_dep_own twin_dep/twin_dep twin_dep_through_lib])
    on_the_device(printed, "twin_dep_own 3\ntwin_dep_through_lib 3\n")
  end

  # A C++ extension links the NDK's shared C++ runtime, libc++_shared.so
  # (phone-projects.md, "The C++ runtime rule"), so that it and a C++
  # library it links, here one a gem's own build links over that
  # runtime too, share one C++ runtime, as a desktop's extension and
  # library share the system's: a string, an exception, type
  # information, the current exception, the terminate handler, and an
  # allocation all cross between them. With a static runtime of its own
  # the extension printed twin_cxx_shares_cout 0, and an app whose
  # extension called such a library this way aborted where a desktop
  # answered each crossing
  # (doc/contributors/research/2026-11-20-two-cxx-runtimes.md). The
  # extension exports nothing of the C++ runtime, holding none of it.
  def test_a_cpp_extension_shares_the_cpp_runtime_of_a_library_it_links
    gem = extconf_gem("twin_cxx", <<~RUBY, "twin_cxx.cpp" => <<~CXX, "lib.mk" => <<~MAKE, "twin/dep.cpp" => <<~DEP)
      require "mkmf"
      create_makefile("twin_cxx/twin_cxx")
      File.open("Makefile", "a") { |makefile| makefile.puts "include $(srcdir)/lib.mk" }
    RUBY
      #include <cstring>
      #include <exception>
      #include <iostream>
      #include <stdexcept>
      #include <string>
      #include <typeinfo>
      #include <ruby.h>
      extern "C" const void *twin_cxx_lib_cout(void);
      std::string twin_cxx_lib_greet(const std::string &name);
      void twin_cxx_lib_raise(void);
      const std::type_info &twin_cxx_lib_kind(void);
      bool twin_cxx_lib_has_current(void);
      void twin_cxx_lib_set_terminate(void);
      int *twin_cxx_lib_new(void);
      extern "C" long twin_cxx_shares_cout(void) { std::cout.flush(); return twin_cxx_lib_cout() == static_cast<const void *>(&std::cout); }
      extern "C" long twin_cxx_greets(void) { return twin_cxx_lib_greet("phone") == "hello phone"; }
      extern "C" long twin_cxx_catches(void) {
        try { twin_cxx_lib_raise(); } catch (const std::exception &error) { return std::strcmp(error.what(), "boom") == 0; }
        return 0;
      }
      extern "C" long twin_cxx_same_type(void) {
        return twin_cxx_lib_kind() == typeid(std::runtime_error) && &twin_cxx_lib_kind() == &typeid(std::runtime_error);
      }
      extern "C" long twin_cxx_current(void) {
        try { twin_cxx_lib_raise(); } catch (...) { return twin_cxx_lib_has_current(); }
        return 0;
      }
      extern "C" long twin_cxx_terminate(void) {
        std::terminate_handler before = std::get_terminate();
        twin_cxx_lib_set_terminate();
        return std::get_terminate() != before;
      }
      extern "C" long twin_cxx_deletes(void) { int *seven = twin_cxx_lib_new(); long value = *seven; delete seven; return value; }
      extern "C" void Init_twin_cxx(void) { rb_define_module("TwinCxx"); }
    CXX
      LIBDEP = $(shell pwd)/libdep/libtwin_cxx_lib.so
      LOCAL_LIBS += -L$(shell pwd)/libdep -ltwin_cxx_lib
      $(OBJS): $(LIBDEP)
      $(LIBDEP):
      \tmkdir -p $(@D) && $$CXX -shared -fPIC $(srcdir)/twin/dep.cpp -o $@ && cp "$$($$CXX -print-file-name=libc++_shared.so)" $(@D)/
    MAKE
      #include <cstdlib>
      #include <exception>
      #include <iostream>
      #include <stdexcept>
      #include <string>
      #include <typeinfo>
      extern "C" const void *twin_cxx_lib_cout(void) { return &std::cout; }
      std::string twin_cxx_lib_greet(const std::string &name) { return "hello " + name; }
      void twin_cxx_lib_raise(void) { throw std::runtime_error("boom"); }
      const std::type_info &twin_cxx_lib_kind(void) { return typeid(std::runtime_error); }
      bool twin_cxx_lib_has_current(void) { return static_cast<bool>(std::current_exception()); }
      static void twin_cxx_lib_terminate(void) { std::abort(); }
      void twin_cxx_lib_set_terminate(void) { std::set_terminate(twin_cxx_lib_terminate); }
      int *twin_cxx_lib_new(void) { return new int(7); }
    DEP

    built = compile(gem)

    crossings = %w[shares_cout greets catches same_type current terminate deletes]
    printed = on_device(built, crossings.flat_map { |crossing| ["twin_cxx/twin_cxx", "twin_cxx_#{crossing}"] })
    built.targets.each_value do |target|
      library = target.libraries.fetch(0)
      assert_includes needed(target, library.path), "libc++_shared.so", "#{target.target.name}: the extension links the shared C++ runtime"
      symbols = dynamic_symbols(target, library.path)
      exported = defined(symbols)
      runtime = runtime_names(target, exported)
      assert_equal [], runtime.first(5),
        "#{target.target.name}: #{runtime.size} of the #{exported.size} symbols #{File.basename(library.path)} " \
          "(#{File.size(library.path)} bytes) exports are the C++ runtime's; on the device: #{printed.inspect}"
      assert_match(/ Init_twin_cxx$/, symbols, "#{target.target.name}: dln finds the Init function")
    end
    on_the_device(printed, crossings.map { |crossing| "twin_cxx_#{crossing} #{(crossing == 'deletes') ? 7 : 1}\n" }.join)
  end

  # A path gem +name+ whose extension calls fledge_twin, from a static
  # library whose definition returns +number+, in +name+_value.
  private def twin(name, number)
    extconf_gem(name, <<~RUBY, "twin/lib.c" => "int fledge_twin(void) { return #{number}; }\n", "#{name}.c" => <<~C, "lib.mk" => ARCHIVE)
      require "mkmf"
      create_makefile("#{name}/#{name}")
      File.open("Makefile", "a") { |makefile| makefile.puts "include $(srcdir)/lib.mk" }
    RUBY
      #include <ruby.h>
      int fledge_twin(void);
      long #{name}_value(void) { return fledge_twin(); }
      void Init_#{name}(void) { rb_define_module("Twin"); }
    C
  end

  # The dynamic symbols of +path+, by the NDK's llvm-readelf.
  private def dynamic_symbols(target, path)
    readelf = File.join(File.dirname(target.target.environment.fetch("FLEDGE_CC")), "llvm-readelf")
    read, status = Open3.capture2(readelf, "--dyn-syms", "-W", path)
    assert_predicate status, :success?, "llvm-readelf reads #{path}"
    read
  end

  # The names +symbols+, what llvm-readelf --dyn-syms printed, defines
  # and exports.
  private def defined(symbols)
    symbols.lines.grep(/\s(?:GLOBAL|WEAK)\s+DEFAULT\s+\d+\s/).map { |line| line.split.last }
  end

  # The names of +exported+, what an extension file exports, that are
  # the C++ runtime's: those the NDK's libc++_shared.so for +target+
  # defines, and the unwinder's
  # (UNWINDER). An extension file that held a copy of the runtime and
  # exported it would define these. What else it exports of std:: is
  # its own: a template instance its code made from libc++'s headers,
  # as a desktop's extension makes and exports one, such as the
  # basic_string constructor from a const char * that arm64's
  # extension here keeps out of line and x86_64's inlines.
  private def runtime_names(target, exported)
    ndk_lib = File.join(File.dirname(target.target.environment.fetch("FLEDGE_CC")), "..", "sysroot", "usr", "lib", target.target.name)
    shared = defined(dynamic_symbols(target, File.join(ndk_lib, "libc++_shared.so")))
    assert_includes shared, "__cxa_begin_catch", "#{target.target.name}: libc++_shared.so defines the C++ runtime"
    exported.select { |name| shared.include?(name) || name.match?(UNWINDER) }
  end

  # The libraries +path+ names as needed, by the NDK's llvm-readelf.
  private def needed(target, path)
    readelf = File.join(File.dirname(target.target.environment.fetch("FLEDGE_CC")), "llvm-readelf")
    read, status = Open3.capture2(readelf, "--needed-libs", path)
    assert_predicate status, :success?, "llvm-readelf reads #{path}"
    read.split
  end

  # What HOST prints on the attached device for +arguments+, pairs of an
  # extension's feature and a function: the extensions built for the
  # device's ABI, with every library beside them and libfledgeruby.so,
  # pushed to a folder of the device's own, where LD_LIBRARY_PATH names
  # the folder, as an app's namespace names its native library folder.
  # Or +nil+ with no device attached.
  private def on_device(built, arguments)
    return unless ENV["ANDROID_SERIAL"]

    abi = adb("shell", "getprop", "ro.product.cpu.abi").strip
    target = built.targets.values.find { |build| build.target.abi == abi } or flunk "nothing was built for #{abi}"
    local = File.join(@dir, "device")
    FileUtils.mkdir_p(local)
    File.write(File.join(local, "host.c"), HOST)
    Fledge::Command.run(target.target.environment.fetch("FLEDGE_CC"), "-fPIE", "-pie", File.join(local, "host.c"), "-o", File.join(local, "host"),
      install: "Install the Android NDK again: its clang does not compile.")
    names = target.libraries.to_h do |library|
      Dir.glob(File.join(File.dirname(library.path), "**", "*.so")).each { |file| FileUtils.cp(file, local) }
      [library.feature, File.basename(library.path)]
    end
    FileUtils.cp(File.join(target.target.libdir, "libfledgeruby.so"), local)
    remote = "/data/local/tmp/fledge-symbols-#{Process.pid}"
    adb("shell", "rm -rf #{remote} && mkdir -p #{remote}")
    Dir.children(local).each { |file| adb("push", File.join(local, file), "#{remote}/#{file}") }
    command = arguments.each_slice(2).flat_map { |feature, function| ["./#{names.fetch(feature)}", function] }
    adb("shell", "cd #{remote} && chmod 755 host && LD_LIBRARY_PATH=#{remote} ./host #{command.join(' ')}; status=$?; rm -rf #{remote}; exit $status")
  end

  # Checks that the device printed +expected+, or skips with no device.
  private def on_the_device(printed, expected)
    android_missing "no Android device or emulator: set ANDROID_SERIAL, as bin/android-emulator does" unless printed

    assert_equal expected, printed
  end

  private def adb(*arguments)
    out, status = Open3.capture2e("adb", *arguments)
    assert_predicate status, :success?, "adb #{arguments.join(' ')}:\n#{out}"
    out.delete("\r")
  end

  private def compile(*gems)
    runtimes_dir = real_runtimes
    ndk_check
    env = ENV.to_h.merge("FLEDGE_RUNTIME_DIR" => runtimes_dir)
    runtimes = Fledge::Runtimes.new(env:)
    phone = Fledge::MobilePlatform.find("android")
    tree = File.join(@dir, "tree")
    Fledge::Archive.unpack(runtimes.archive(phone), into: tree)
    log = StringIO.new
    Fledge::MobileExtensions.new(platform: phone, packages: gems.to_h { |gem| [gem, Fledge::PathPackage.new(gem)] }, build_args: {},
      host: Fledge::Platform.local, runtimes:, work: File.join(@dir, "work"), log:, gem_dir: "lib/ruby/gems/4.1.0+5", env:, files: true)
      .call(File.join(tree, Dir.children(tree).first))
  rescue Fledge::Error => e
    raise Fledge::Error, "#{e.message}\n#{log&.string}"
  end

  # A path gem +name+ with +extconf+ and +files+ in ext/+name+. mkmf
  # compiles every source in that folder into the extension, so a
  # library's sources go in a folder below it (twin/).
  private def extconf_gem(name, extconf, files = {})
    folder = File.join(@dir, "gems", name)
    FileUtils.mkdir_p(File.join(folder, "ext", name))
    File.write(File.join(folder, "ext", name, "extconf.rb"), extconf)
    files.each do |file, text|
      path = File.join(folder, "ext", name, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
    File.write(File.join(folder, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = "1.0.0"
        spec.authors = ["Kerrick Long"]
        spec.summary = "An extconf.rb's extension"
        spec.files = #{(["ext/#{name}/extconf.rb"] + files.keys.map { |file| "ext/#{name}/#{file}" }).inspect}
        spec.extensions = ["ext/#{name}/extconf.rb"]
      end
    RUBY
    Fledge::PathGem.new(name:, version: "1.0.0", folder:, app_path: "vendor/cache/#{name}", glob: "{,*,*/*}.gemspec", inside: true)
  end

  private def ndk_check
    Fledge::MobileExtensions::NDK.find(ENV, host: Fledge::Platform.local)
  rescue Fledge::Error => e
    android_missing(e.message)
  end

  private def real_runtimes
    dir = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    phone = File.join(dir, Fledge::Runtimes.file_name(Fledge::MobilePlatform.find("android")))
    android_missing "no #{File.basename(phone)} in #{dir}; run bundle exec rake runtime[android]" unless File.file?(phone)
    dir
  end
end
