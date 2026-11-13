# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"
require "shellwords"
require_relative "archive"
require_relative "command"
require_relative "error"
require_relative "gem_package"
require_relative "git_package"
require_relative "path_package"
require_relative "native_build"
require_relative "mobile_extensions/cmake"
require_relative "mobile_extensions/linking"
require_relative "mobile_extensions/ndk"
require_relative "mobile_extensions/rake_build"
require_relative "mobile_extensions/rust"

module Fledge
  # Compiles an app's gems' C, C++, and Rust extensions for a phone (ADR 022).
  #
  # A phone's Ruby loads no extension from a file (ADR 011), so
  # each one is compiled to a static archive, linked into the app, and
  # registered under the name <tt>require</tt> asks for, which Ruby's own
  # <tt>extinit.c</tt> does for the extensions of its standard library.
  # Ruby's own tool for compiling an extension is mkmf, which an
  # <tt>extconf.rb</tt> requires, and it cross-compiles as it does inside
  # Ruby's build: this class runs each gem's <tt>extconf.rb</tt> with the
  # runtime's Ruby for this computer (the very Ruby Fledge's desktop
  # runtime is), given the <tt>rbconfig.rb</tt> of the phone's runtime and
  # the compiler of this computer's Xcode or Android NDK in place of the
  # one that file records, and then <tt>make static</tt>, which mkmf writes
  # a rule for, as Ruby's <tt>ext/extmk.rb</tt> does for the extensions it
  # links in. mkmf renames each extension's <tt>Init_</tt> function so that
  # two extensions cannot clash, as extmk does (<tt>-DInit_cparse=Init_racc_cparse</tt>),
  # and the registration unit (.registration_source) names the new
  # ones. Fledge::MobileProject::IOS and Fledge::MobileProject::Android
  # link the archives into the app as each system needs. An
  # <tt>extconf.rb</tt> that runs CMake first finds the target's CMake
  # toolchain file in <tt>CMAKE_TOOLCHAIN_FILE</tt> (CMake, ADR 027). An
  # <tt>extconf.rb</tt> that writes rb-sys's Makefile instead has Cargo
  # build a static library for the target (Rust), which keeps the
  # <tt>Init_</tt> function rb-sys names after the extension. Each
  # <tt>extconf.rb</tt> finds the gems its gem depends on, such as
  # rb_sys, on its load path.
  #
  # It compiles for every target of the phone, one after the other: the
  # device and the Simulator slices for iOS, which Xcode builds on a Mac;
  # arm64-v8a and x86_64 for Android, which the NDK builds on a Mac or on
  # x86-64 Linux. It refuses an extension that no <tt>extconf.rb</tt>
  # builds, naming the gem and what to do (.problems).
  #
  # Use it once in <tt>fledge build ios</tt> and <tt>fledge build
  # android</tt>, for an app with a gem that has an extension.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   compiler = Fledge::MobileExtensions.new(platform:, packages: { gem => package }, build_args: {}, host:, runtimes:, work:, log: $stderr)
  #   built = compiler.call(runtime_tree)
  #   built.registrations # => [["adder/adder", "Init_fledge_0"]]
  #   built.targets.keys  # => ["ios-arm64", "ios-arm64-simulator"]
  #--
  # SPDX-SnippetEnd
  #++
  class MobileExtensions
    # The environment variables of the developer's own toolchain that
    # must not reach a cross compile: those mkmf and make read, and those
    # CMake reads besides (cmake-env-variables(7)) that would aim a CMake
    # build an extconf.rb runs at this computer.
    FOREIGN = %w[
      CC
      CXX
      CPP
      CFLAGS
      CXXFLAGS
      CPPFLAGS
      LDFLAGS
      SDKROOT
      IPHONEOS_DEPLOYMENT_TARGET
      MACOSX_DEPLOYMENT_TARGET
      MAKEFLAGS
      CMAKE_OSX_ARCHITECTURES
      OBJC
      OBJCXX
      OBJCFLAGS
      OBJCXXFLAGS
    ].freeze

    # How to get Xcode, for the message when its tools are missing.
    INSTALL_XCODE = "Install Xcode from the App Store or developer.apple.com, and run xcode-select --install."

    # What the runtime's Ruby loads before it reads a phone's
    # <tt>rbconfig.rb</tt> for a build: the phone's tools in place of the
    # ones that file records (a build machine's paths), and, when
    # +FLEDGE_RUBY+ names it, this computer's Ruby in place of the phone's,
    # which cannot run here, so that a build that starts Ruby again
    # (<tt>RbConfig.ruby</tt>, mkmf's <tt>$(RUBY)</tt>) starts this one.
    TOOLS = <<~RUBY
      require "rbconfig"
      {
        "CC" => "FLEDGE_CC", "CXX" => "FLEDGE_CXX", "AR" => "FLEDGE_AR", "RANLIB" => "FLEDGE_RANLIB",
        "rubyhdrdir" => "FLEDGE_HEADERS", "rubyarchhdrdir" => "FLEDGE_HEADERS",
        "LIBRUBYARG" => "FLEDGE_LIBRUBYARG", "LIBRUBYARG_STATIC" => "FLEDGE_LIBRUBYARG",
      }.each do |key, name|
        next unless ENV.key?(name)

        [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].each { |config| config[key] = ENV.fetch(name).dup }
      end
      if ENV.key?("FLEDGE_RUBY")
        ruby = ENV.fetch("FLEDGE_RUBY")
        { "bindir" => File.dirname(ruby), "ruby_install_name" => File.basename(ruby), "EXEEXT" => "" }.each do |key, value|
          [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].each { |config| config[key] = value.dup }
        end
      end
    RUBY

    # What the runtime's Ruby loads before an <tt>extconf.rb</tt>: the
    # phone's tools (TOOLS), and mkmf made to write a static archive
    # and a report. mkmf's own <tt>$static</tt> is what Ruby's
    # <tt>ext/extmk.rb</tt> sets for an extension it links in (line 651).
    # The Init function's new name goes into <tt>$CPPFLAGS</tt>, which mkmf
    # writes into the Makefile's +CPPFLAGS+ always, not <tt>$defs</tt>,
    # which it leaves out once an <tt>extconf.rb</tt> has called
    # <tt>create_header</tt> (<tt>mkmf.rb</tt>, lines 2133 and 2175).
    SHIM = TOOLS + <<~'RUBY'
      require "json"
      require "mkmf"
      $static = true
      module MakeMakefile
        alias_method :fledge_create_makefile, :create_makefile
        def create_makefile(target, *rest, &block)
          $CPPFLAGS << " -DInit_#{File.basename(target)}=#{ENV.fetch('FLEDGE_INIT')}"
          result = fledge_create_makefile(target, *rest, &block)
          reports = File.exist?(ENV.fetch("FLEDGE_REPORT")) ? JSON.parse(File.read(ENV.fetch("FLEDGE_REPORT"))) : []
          reports << {
            "feature" => target, "archive" => "#{File.basename(target)}.#{CONFIG['LIBEXT']}",
            "libs" => $libs, "dir" => Dir.pwd
          }
          File.write(ENV.fetch("FLEDGE_REPORT"), JSON.generate(reports))
          result
        end
      end
    RUBY

    # What the extensions of one target came to: the archives mkmf made,
    # the flags that link them (libraries, frameworks, and paths their
    # extconf.rb added), and whether any is C++, whose runtime the link
    # must bring.
    class TargetBuild < Data.define(:target, :archives, :flags, :cxx)
      ##
      # :attr_reader: target
      # The Target compiled for.

      ##
      # :attr_reader: archives
      # The static archive of each extension, in the order of Built#registrations.

      ##
      # :attr_reader: flags
      # The linker flags the extensions' extconf.rb files asked for.

      ##
      # :attr_reader: cxx
      # Whether any extension has C++ sources.
    end

    # What one extension's build came to: the feature it registers under,
    # its renamed Init function, its archive, the flags its extconf.rb asked
    # for, and whether it has C++.
    class Report < Data.define(:feature, :init, :archive, :flags, :cxx)
      ##
      # :attr_reader: feature
      # The name <tt>require</tt> asks for, such as <tt>"adder/adder"</tt>.

      ##
      # :attr_reader: init
      # The extension's Init function as mkmf renamed it.

      ##
      # :attr_reader: archive
      # The static archive's path.

      ##
      # :attr_reader: flags
      # The linker flags (MobileExtensions.link_flags).

      ##
      # :attr_reader: cxx
      # Whether any source is C++.
    end

    # One compiler target: its name (an XCFramework slice, or an Android
    # ABI's platform), the Ruby's architecture, the folder of the
    # runtime's Ruby for it, and the environment for the shim.
    class Target < Data.define(:name, :root, :arch_dir, :libdir, :environment, :abi)
      ##
      # :attr_reader: name
      # <tt>"ios-arm64"</tt>, or <tt>"aarch64-linux-android"</tt>.

      ##
      # :attr_reader: root
      # The runtime's Ruby for the target: an XCFramework slice, or the runtime.

      ##
      # :attr_reader: arch_dir
      # The folder of the target's rbconfig.rb.

      ##
      # :attr_reader: libdir
      # The folder of the library that holds Ruby, which an Android link names.

      ##
      # :attr_reader: environment
      # The shim's variables (SHIM) for the target.

      ##
      # :attr_reader: abi
      # Android's name for the target (<tt>"arm64-v8a"</tt>), or +nil+.
    end

    # What #call returns: the extensions to register, as pairs of the name
    # <tt>require</tt> asks for and the function that initializes it (the
    # same for every target), and what each target compiled to.
    class Built < Data.define(:registrations, :targets, :ndk)
      ##
      # :attr_reader: registrations
      # Pairs of the feature (<tt>"adder/adder"</tt>) and its renamed Init function.

      ##
      # :attr_reader: targets
      # Each target's TargetBuild, by the target's name.

      ##
      # :attr_reader: ndk
      # The NDK::NDK that compiled them, for Android; +nil+ for iOS.
    end

    # Why each of the gem's extensions cannot be compiled for +platform+
    # from +host+, as sentences naming +gem+ and what to do, or none:
    # an extension that something other than an <tt>extconf.rb</tt>
    # builds (Rake, CMake, configure, Cargo), and, for Android, a
    # computer the NDK's toolchain does not run on here.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions.problems(gem, package, ios, host) # => []
    #--
    # SPDX-SnippetEnd
    #++
    def self.problems(gem, package, platform, host)
      return [] unless package.extensions?

      spec = package.spec
      advice = "Leave it out of the app's #{platform} build (gem \"#{gem.name}\", platforms: [...] in the Gemfile)"
      other = spec.extensions.reject { |path| File.basename(path) == "extconf.rb" || rake?(path) }
      unless other.empty?
        return [
"#{gem} has an extension built by #{other.join(', ')}, and Fledge compiles for #{platform} only extensions that an " \
  "extconf.rb or a Rakefile builds (an extconf.rb may run CMake first). #{advice}, or ask its author for an extconf.rb.",
]
      end
      if platform.name == "android" && host.windows?
        return [
"#{gem} has an extension to compile for android, and Fledge compiles those on a Mac or Linux, and this computer " \
  "is #{host}. Build the project on one, or leave the gem out of the app's android build.",
]
      end

      []
    end

    # The C source of the registration unit (ADR 022): for each of
    # +registrations+, the pairs #call returns, it declares the extension's
    # Init function and registers it by the name <tt>require</tt> asks for
    # (<tt>fledge_ruby_add_extension</tt>), from a constructor, so that the
    # unit needs no call from the host app, whatever host it is.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions.registration_source([["adder/adder", "Init_fledge_0"]])
    #   # => "... fledge_ruby_add_extension(\"adder/adder\", Init_fledge_0); ..."
    #--
    # SPDX-SnippetEnd
    #++
    def self.registration_source(registrations)
      declarations = registrations.map { |_, init| "extern void #{init}(void);\n" }.join
      calls = registrations.map { |feature, init| "    fledge_ruby_add_extension(#{c_string(feature)}, #{init});\n" }.join
      <<~C
        /*
         * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
         * SPDX-License-Identifier: MIT
         */

        /*
         * Written by fledge build (ADR 022): registers the extensions of this
         * app's gems, which are linked into it, so that require finds them.
         * Ruby registers them once it has booted, before the program runs.
         */
        #include <fledge_ruby.h>

        #{declarations.chomp.gsub("\n", "\n#{' ' * 8}")}

        __attribute__((constructor)) static void
        fledge_register_extensions(void)
        {
        #{calls.chomp}
        }
      C
    end

    # Whether RubyGems builds the extension at +path+ with Rake, as
    # <tt>Gem::Ext::Builder#builder_for</tt> chooses: a path that names
    # a Rakefile or an <tt>mkrf_conf</tt> script, and neither an
    # <tt>extconf</tt> nor a <tt>configure</tt>, which it tries first.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileExtensions.rake?("ext/digest/Rakefile") # => true
    #--
    # SPDX-SnippetEnd
    #++
    def self.rake?(path)
      !path.match?(/extconf|configure/) && path.match?(/rakefile|mkrf_conf/i)
    end

    # +text+ as a C string literal.
    def self.c_string(text)
      "\"#{text.gsub(/["\\]/) { |character| "\\#{character}" }}\""
    end
    private_class_method :c_string

    # Creates the compiler.
    #
    # [platform] The Fledge::MobilePlatform compiled for.
    # [packages] The app's gems' packages by gem (Fledge::GemPackage,
    #            Fledge::GitPackage, or Fledge::PathPackage); those with
    #            an extension are compiled.
    # [build_args] Each gem's build options by its name, which are its
    #              extconf.rb's arguments.
    # [host] The Fledge::Platform of this computer.
    # [runtimes] The Fledge::Runtimes that finds this computer's runtime,
    #            whose Ruby runs mkmf.
    # [work] A folder of the build's own, which the caller removes.
    # [log] Where the compilers' output goes, such as <tt>$stderr</tt>.
    # [env] The environment to start from (default: +ENV+).
    # [dependencies] The packages of the gems those gems depend on, by
    #                gem (default: none), whose code an extconf.rb may
    #                require, as rb-sys's is.
    def initialize(platform:, packages:, build_args:, host:, runtimes:, work:, log:, env: ENV, dependencies: {})
      @platform = platform
      @packages = packages
      @dependencies = dependencies
      @build_args = build_args
      @host = host
      @runtimes = runtimes
      @work = work
      @log = log
      @env = env
      @ruby = nil # : String?
      @rake_build = nil # : RakeBuild?
      @load_path = nil # : Array[String]?
    end

    # Compiles each gem with an extension, for every target of the phone,
    # against the runtime unpacked at +tree+, and returns a Built. Raises
    # Fledge::Error when a compiler or tool is missing or a gem's
    # extension does not compile, naming the gem and target; the
    # compiler's output is in the log.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   compiler.call(tree).registrations.size # => 1
    #--
    # SPDX-SnippetEnd
    #++
    def call(tree)
      wanted = @packages.select { |_, package| package.extensions? }
      ndk = (@platform.name == "android") ? NDK.find(@env, host: @host) : nil
      targets = targets(tree, ndk)
      registrations = [] # : Array[[String, String]]
      builds = targets.to_h do |target|
        reports = [] # : Array[Report]
        wanted.each do |gem, package|
          reports.concat(compile(target, gem, package, @build_args.fetch(gem.name, []), reports.size))
        end
        found = reports.map { |report| [report.feature, report.init] }
        unless registrations.empty? || found == registrations
          raise Error, "the app's gems built different extensions for each target of #{@platform}: #{registrations.to_h.keys} and #{found.to_h.keys}"
        end

        registrations = found
        [target.name, Linking.target_build(target, reports)]
      end
      clash = registrations.group_by(&:last).values.find { |pairs| pairs.size > 1 }
      raise Error, "The extensions #{clash.map(&:first).join(' and ')} both start with #{clash.first.last}, and one app can link only one" if clash
      Built.new(registrations:, targets: builds, ndk:)
    end

    # Links the shared library an Android app loads, +into+ it, for the
    # target of +build+: the registration unit's C file +registration+ and
    # the extensions' archives, against the runtime's
    # <tt>libfledgeruby.so</tt>, aligned for 16 KB pages as the runtime's
    # own library is, with the NDK's C++ runtime linked statically (a shared one would be a
    # library the package does not carry) when an extension has C++, and
    # with its run path <tt>$ORIGIN</tt>, so that the runtime's ruby
    # program, which loads it outside the app's own library namespace,
    # finds the shared libraries it needs beside it (ADR 069). Returns +into+.
    def shared_library(built, build, registration:, into:)
      ndk = built.ndk or raise Error, "only an Android app links a shared library"
      target = build.target
      cc = target.environment.fetch("FLEDGE_CC")
      cc = "#{cc}++" if build.cxx
      stl = build.cxx ? ["-static-libstdc++"] : [] # : Array[String]
      FileUtils.mkdir_p(File.dirname(into))
      run(clean_env, cc, "-shared", "-fPIC", "-O2", "-I", File.join(target.root, "include"), "-o", into, *stl, "-x", "c", registration, "-x", "none",
        *build.archives, "-L#{target.libdir}", "-lfledgeruby", *build.flags, "-llog", "-lm", "-Wl,-z,max-page-size=16384",
        "-Wl,--exclude-libs,ALL", "-Wl,-rpath,$ORIGIN", what: "linking the app's extensions for #{target.name} with #{File.basename(ndk.root)}")
      run(clean_env, File.join(ndk.bin, "llvm-strip"), "--strip-unneeded", into, what: "stripping #{File.basename(into)} for #{target.name}")
      into
    end

    # The compilers' targets for the runtime unpacked at +tree+.
    private def targets(tree, ndk)
      if ndk
        aar = unpack_aar(File.join(tree, "FledgeRuby.aar"))
        ANDROID_ABIS.map { |arch, abi| android_target(arch, abi, tree, aar, ndk) }
      else
        IOS_SLICES.map { |slice| ios_target(slice, File.join(tree, "FledgeRuby.xcframework", slice)) }
      end
    end

    # The XCFramework's slices, the device's and the Simulator's.
    IOS_SLICES = %w[ios-arm64 ios-arm64-simulator].freeze
    private_constant :IOS_SLICES

    # The Android targets' Ruby architectures, and the ABI Android calls each.
    ANDROID_ABIS = { "aarch64-linux-android" => "arm64-v8a", "x86_64-linux-android" => "x86_64" }.freeze
    private_constant :ANDROID_ABIS

    # The slice's tools: Xcode's clang for the slice's SDK, aimed at the
    # triple the runtime was built for (which its rbconfig.rb records),
    # the slice's headers, which sit beside its library and not where
    # rbconfig.rb says, and a CMake toolchain file for the same.
    private def ios_target(slice, root)
      sdk = slice.end_with?("-simulator") ? "iphonesimulator" : "iphoneos"
      arch_dir = rbconfig_dir(root)
      triple = recorded_compiler(arch_dir)[/-target (\S+)/, 1] or raise Error, "#{arch_dir}/rbconfig.rb records no target triple"
      sysroot = xcrun(sdk, "--show-sdk-path")
      cc = xcrun(sdk, "--find", "clang")
      cxx = xcrun(sdk, "--find", "clang++")
      environment = {
        "FLEDGE_CC" => "#{cc} -target #{triple} -isysroot #{sysroot}",
        "FLEDGE_CXX" => "#{cxx} -target #{triple} -isysroot #{sysroot}",
        "FLEDGE_HEADERS" => File.join(root, "Headers"),
        "FLEDGE_LIBRUBYARG" => "-L#{root} -lfledgeruby -lz $(MAINLIBS) -framework Security -framework CoreFoundation",
        "CMAKE_TOOLCHAIN_FILE" => toolchain_file(slice, CMake.ios(triple:, sysroot:, cc:, cxx:)),
        **Rust.ios(slice, triple:, sysroot:),
      }
      Target.new(name: slice, root:, arch_dir:, libdir: root, environment: with_tools(environment), abi: nil)
    end

    # The ABI's tools: the NDK's clang of the very name the runtime was
    # built with, its llvm-ar and llvm-ranlib, the library that holds
    # Ruby, from the AAR, and a CMake toolchain file for the same.
    private def android_target(arch, abi, tree, aar, ndk)
      arch_dir = File.join(tree, "lib", "ruby", Dir.children(File.join(tree, "lib", "ruby")).grep(/\A\d/).first.to_s, arch)
      compiler = File.basename(recorded_compiler(arch_dir))
      cc = File.join(ndk.bin, compiler)
      raise Error, "#{ndk.root} has no #{compiler}, which Android's Ruby was built with" unless File.file?(cc)

      libdir = File.join(aar, "jni", abi)
      environment = {
        "FLEDGE_CC" => cc,
        "FLEDGE_CXX" => "#{cc}++",
        "FLEDGE_AR" => File.join(ndk.bin, "llvm-ar"),
        "FLEDGE_RANLIB" => File.join(ndk.bin, "llvm-ranlib"),
        "FLEDGE_LIBRUBYARG" => "-L#{libdir} -lfledgeruby",
        "CMAKE_TOOLCHAIN_FILE" => toolchain_file(arch, CMake.android(ndk: ndk.root, abi:, compiler:)),
        **Rust.android(arch, bin: ndk.bin, cc:, resource: resource_dir(cc, ndk)),
      }
      Target.new(name: arch, root: tree, arch_dir:, libdir:, environment: with_tools(environment), abi:)
    end

    # +environment+, a target's, with the phone's tools also under the
    # names autoconf and make read, CC, CXX, AR, and RANLIB, in place of
    # the developer's (FOREIGN), so that a build an extension's Makefile
    # starts is aimed at the phone too: the ffi gem's runs libffi's
    # configure with no compiler of its own on Android
    # (<tt>ext/ffi_c/libffi.mk</tt> at 1.17.4), as a cross build's
    # environment names the target's compiler for rake-compiler-dock and
    # crossenv. And no pkg-config, as the runtime's own configure is
    # given none (PKG_CONFIG=false): pkg-config finds this computer's
    # libraries, not the phone's, and mkmf runs it, where the phone's
    # rbconfig.rb names none, as the environment's PKG_CONFIG names it
    # (<tt>lib/mkmf.rb</tt>, line 1969 at Ruby 4.1.0-preview1). It found
    # a Mac's libffi for the ffi gem, whose extconf.rb then linked the
    # Simulator's with <tt>-lffi</tt>. A gem's
    # <tt>--with-pkg-config</tt> option still names one.
    private def with_tools(environment)
      tools = %w[CC CXX AR RANLIB].to_h { |name| [name, environment["FLEDGE_#{name}"]] }.compact
      environment.merge(tools, "PKG_CONFIG" => "false")
    end

    # The resource folder of the NDK's compiler +cc+, which holds the
    # headers it brings itself (<tt>stdarg.h</tt> and the rest).
    private def resource_dir(cc, ndk)
      Command.run(cc, "-print-resource-dir", install: "Install the Android NDK again: #{ndk.root} has no working #{File.basename(cc)}.").strip
    end

    # Writes +text+, the CMake toolchain file of the target +name+, into
    # the build's folder, and returns its path.
    private def toolchain_file(name, text)
      path = File.join(@work, "toolchains", "#{name}.cmake")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
      path
    end

    private def xcrun(sdk, *)
      Command.run("xcrun", "--sdk", sdk, *, install: INSTALL_XCODE).strip
    end

    # The folder of the rbconfig.rb under +root+'s lib/ruby.
    private def rbconfig_dir(root)
      path = Dir.glob(File.join(root, "lib", "ruby", "*", "*", "rbconfig.rb")).first or raise Error, "#{root} holds no Ruby for a phone: no rbconfig.rb"
      File.dirname(path)
    end

    # The compiler the rbconfig.rb in +arch_dir+ records.
    private def recorded_compiler(arch_dir)
      path = File.join(arch_dir, "rbconfig.rb")
      File.read(path)[/CONFIG\["CC"\] = "([^"]+)"/, 1] or raise Error, "#{path} records no compiler"
    end

    # The AAR's contents, unpacked once with unzip (an AAR is a zip).
    private def unpack_aar(aar)
      into = File.join(@work, "aar")
      return into if File.directory?(File.join(into, "jni"))

      FileUtils.mkdir_p(into)
      Command.run("unzip", "-q", "-o", aar, "-d", into, install: "Install unzip, which unpacks the Android runtime's AAR.")
      into
    end

    # Compiles +package+'s extensions for +target+, in a folder of their
    # own, and returns a report for each: the archive, its flags, the
    # feature, and its Init function, numbered from +first+.
    private def compile(target, gem, package, args, first)
      root = source_root(package, File.join(@work, target.name, package.spec.full_name))
      rust = package.spec.runtime_dependencies.any? { |dependency| dependency.name == "rb_sys" }
      reports = [] # : Array[Report]
      package.spec.extensions.each do |extension|
        number = first + reports.size
        if self.class.rake?(extension)
          reports.concat(rake_build.call(target, gem, package.spec, root, extension, args, number))
        else
          reports << extconf(target, gem, File.dirname(File.join(root, extension)), File.basename(extension), args, number, rust:)
        end
      end
      reports
    end

    # Compiles the extension an <tt>extconf.rb</tt> in +folder+ builds,
    # with mkmf's <tt>make static</tt>, its Init function renamed
    # <tt>Init_fledge_NUMBER</tt>, or, when its gem depends on rb_sys
    # (+rust+), with Cargo (Rust::SHIM and #make). The gems its gem
    # depends on are on its load path (#load_path).
    private def extconf(target, gem, folder, extconf, args, number, rust:)
      init = "Init_fledge_#{number}"
      report = File.join(folder, "fledge-report.json")
      env = clean_env.merge(target.environment).merge("FLEDGE_INIT" => init, "FLEDGE_REPORT" => report, **RUST_FILES)
      what = "compiling #{gem}'s extension #{extconf} for #{target.name}"
      includes = [target.arch_dir, *load_path].flat_map { |path| ["-I", path] }
      shims = rust ? [shim_path, rust_shim_path] : [shim_path]
      run(env, ruby, "--disable-gems", *includes, *shims.flat_map { |shim| ["-r", shim] }, extconf, *args, chdir: folder, what:)
      reports = JSON.parse(File.read(report))
      make(env, reports, folder, gem, target, what:)
      describe(reports, folder, init, gem, target, env)
    end

    # The builder of extensions a Rakefile builds (RakeBuild).
    private def rake_build
      @rake_build ||= RakeBuild.new(ruby:, work: @work, environment: clean_env, run: method(:run))
    end

    # The names of the files a Rust extension's build writes in its
    # folder (Rust::SHIM).
    RUST_FILES = {
      "FLEDGE_RUST_NATIVE_LIBS" => Rust::NATIVE_LIBS, "FLEDGE_RUST_LIBRARY" => Rust::LIBRARY, "FLEDGE_RUST_MAKEFILE" => Rust::MAKEFILE
    }.freeze
    private_constant :RUST_FILES

    # Runs the Makefile the extconf.rb in +folder+ wrote: <tt>make
    # static</tt> for mkmf's, which makes the static archive, or for
    # rb-sys's, the goal that has Cargo make the static library, with the
    # Makefile's own Cargo arguments, which the shim made from the
    # developer's RB_SYS_EXTRA_CARGO_ARGS where it is set.
    private def make(env, reports, folder, gem, target, what:)
      return run(env, "make", "static", chdir: folder, what:) unless reports.any? { |report| report["rust"] }

      triple = target.environment.fetch("CARGO_BUILD_TARGET")
      Rust.check(triple, gem: gem.to_s, env:)
      run(env.merge("RB_SYS_EXTRA_CARGO_ARGS" => nil), "make", "-f", Rust::MAKEFILE, "SOEXT=a", "fledge-rust", chdir: folder, what:)
    end

    # What one extension's build came to, from the shim's +reports+ and
    # the Makefile in +folder+, which make reads with +env+.
    private def describe(reports, folder, init, gem, target, env)
      raise Error, "#{gem}'s extconf.rb called create_makefile #{reports.size} times, and Fledge links one extension for each" if reports.size != 1

      report = reports.first
      return describe_rust(report, folder, gem, target) if report["rust"]

      archive = File.join(folder, report.fetch("archive"))
      raise Error, "#{gem}'s extension made no #{File.basename(archive)} for #{target.name}" unless File.file?(archive)

      libs = "#{report.fetch('libs')} #{Linking.local_libs(env, folder)}"
      Report.new(
        feature: report.fetch("feature"), init:, archive:, flags: Linking.link_flags(libs, dir: folder),
        cxx: File.read(File.join(folder, "Makefile")).match?(/^ORIG_SRCS = .*\.(?:cc|cpp|cxx|C)(?:\s|$)/) || Linking.cxx_runtime?(libs)
      )
    end

    # What a Rust extension's build in +folder+ came to: the static
    # library Cargo made, which keeps the Init function rb-sys names
    # after the extension, and the native libraries rustc said it needs.
    private def describe_rust(report, folder, gem, target)
      named = File.join(folder, Rust::LIBRARY)
      archive = File.expand_path(File.read(named).strip, folder) if File.file?(named)
      raise Error, "#{gem}'s Rust extension made no static library for #{target.name}" unless archive && File.file?(archive)

      feature = report.fetch("feature")
      libs = File.read(File.join(folder, Rust::NATIVE_LIBS))
      Report.new(feature:, init: "Init_#{File.basename(feature)}", archive:, flags: Rust.link_flags(libs, dir: folder, apple: target.abi.nil?),
        cxx: Linking.cxx_runtime?(libs))
    end

    # The folders of the code of the gems the compiled gems depend on,
    # unpacked once, for each extconf.rb's load path.
    private def load_path
      @load_path ||= @dependencies.values.flat_map do |package|
        root = source_root(package, File.join(@work, "dependencies", package.spec.full_name))
        package.spec.require_paths.map { |path| File.expand_path(path, root) }
      end
    end

    # The gem's files unpacked into +dir+, and the folder its extension
    # paths are relative to.
    private def source_root(package, dir)
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(File.dirname(dir))
      case package
      when GemPackage
        ::Gem::Package.new(package.path).extract_files(dir) # steep:ignore NoMethod
        dir
      when PathPackage
        package.copy_to(dir)
        File.dirname(File.join(dir, package.gemspec))
      when GitPackage
        FileUtils.cp_r(package.checkout, dir)
        FileUtils.rm_rf(File.join(dir, ".git"))
        File.dirname(File.join(dir, package.gemspec))
      else raise Error, "#{package.spec.full_name} is not a gem from a gem server, from git, or from a folder"
      end
    end

    # This computer's runtime's Ruby, which runs mkmf.
    private def ruby
      @ruby ||= begin
        raise Error, "a Windows computer's runtime can't compile extensions for #{@platform}" if @host.windows?

        host = File.join(@work, "host")
        FileUtils.rm_rf(host)
        Archive.unpack(@runtimes.archive(@host), into: host)
        File.join(host, Dir.children(host).first.to_s, "bin", "ruby")
      end
    end

    private def shim_path
      path = File.join(@work, "fledge_mobile_mkmf.rb")
      File.write(path, SHIM)
      path
    end

    private def rust_shim_path
      path = File.join(@work, "fledge_mobile_rb_sys.rb")
      File.write(path, Rust::SHIM)
      path
    end

    private def clean_env
      scrubbed = @env.to_h.keys.grep(NativeBuild::SCRUBBED) + FOREIGN
      scrubbed.to_h { |name| [name, nil] } # : Hash[String, String?]
    end

    private def run(env, *command, what:, chdir: nil)
      @log.puts "#{what[0]&.upcase}#{what[1..]}"
      options = { chdir: chdir || Dir.pwd } # : Hash[Symbol, String]
      status = Open3.popen2e(env, *command, **options) do |_, output, thread| # steep:ignore ArgumentTypeMismatch
        output.each_line { |line| @log.puts line }
        thread.value
      end
      raise Error, "#{what} failed; the tools' output is above" unless status.success?
    rescue SystemCallError => e
      raise Error, "fledge build needs #{File.basename(command.first.to_s)}, which it could not run (#{e.message})"
    end
  end
end
