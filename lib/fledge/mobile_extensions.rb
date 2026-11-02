# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
require_relative "mobile_extensions/linking"
require_relative "mobile_extensions/ndk"

module Fledge
  # Compiles an app's gems' C and C++ extensions for a phone (ADR 022).
  #
  # A phone's Ruby loads no extension from a file (ADR 011, section 4), so
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
  # link the archives into the app as each system needs.
  #
  # It compiles for every target of the phone, one after the other: the
  # device and the Simulator slices for iOS, which Xcode builds on a Mac;
  # arm64-v8a and x86_64 for Android, which the NDK builds on a Mac or on
  # x86-64 Linux. It refuses an extension that mkmf does not build, or that
  # is Rust, naming the gem and what to do (.problems).
  #
  # Use it once in <tt>fledge build ios</tt> and <tt>fledge build
  # android</tt>, for an app with a gem that has an extension.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # must not reach a cross compile.
    FOREIGN = %w[CC CXX CPP CFLAGS CXXFLAGS CPPFLAGS LDFLAGS SDKROOT IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET MAKEFLAGS].freeze

    # How to get Xcode, for the message when its tools are missing.
    INSTALL_XCODE = "Install Xcode from the App Store or developer.apple.com, and run xcode-select --install."

    # What the runtime's Ruby loads before an <tt>extconf.rb</tt>: the
    # phone's tools in place of the ones its <tt>rbconfig.rb</tt> records
    # (a build machine's paths), and mkmf made to write a static archive
    # and a report. mkmf's own <tt>$static</tt> is what Ruby's
    # <tt>ext/extmk.rb</tt> sets for an extension it links in (line 651).
    SHIM = <<~'RUBY'
      require "json"
      require "rbconfig"
      {
        "CC" => "FLEDGE_CC", "CXX" => "FLEDGE_CXX", "AR" => "FLEDGE_AR", "RANLIB" => "FLEDGE_RANLIB",
        "rubyhdrdir" => "FLEDGE_HEADERS", "rubyarchhdrdir" => "FLEDGE_HEADERS",
        "LIBRUBYARG" => "FLEDGE_LIBRUBYARG", "LIBRUBYARG_STATIC" => "FLEDGE_LIBRUBYARG",
      }.each do |key, name|
        next unless ENV.key?(name)

        [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].each { |config| config[key] = ENV.fetch(name).dup }
      end
      require "mkmf"
      $static = true
      module MakeMakefile
        alias_method :fledge_create_makefile, :create_makefile
        def create_makefile(target, *rest, &block)
          $defs << "-DInit_#{File.basename(target)}=#{ENV.fetch('FLEDGE_INIT')}"
          result = fledge_create_makefile(target, *rest, &block)
          reports = File.exist?(ENV.fetch("FLEDGE_REPORT")) ? JSON.parse(File.read(ENV.fetch("FLEDGE_REPORT"))) : []
          reports << {
            "feature" => target, "archive" => "#{File.basename(target)}.#{CONFIG['LIBEXT']}",
            "libs" => [$libs, $LOCAL_LIBS].join(" "), "dir" => Dir.pwd
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
    # builds (Rake, CMake, configure, Cargo), a Rust one, and, for Android,
    # a computer the NDK's toolchain does not run on here.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
      if spec.runtime_dependencies.any? { |dependency| dependency.name == "rb_sys" }
        return [
"#{gem} is a Rust extension (it depends on rb_sys), and Fledge compiles C and C++ extensions for #{platform}, " \
  "not Rust ones yet. #{advice}, or use a gem with a C or C++ extension.",
]
      end
      other = spec.extensions.reject { |path| File.basename(path) == "extconf.rb" }
      unless other.empty?
        return [
"#{gem} has an extension built by #{other.join(', ')}, and Fledge compiles for #{platform} only extensions that an " \
  "extconf.rb builds, with mkmf, as Ruby's own tools do. #{advice}, or ask its author for an extconf.rb.",
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
         * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
         * SPDX-License-Identifier: AGPL-3.0-or-later
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
    def initialize(platform:, packages:, build_args:, host:, runtimes:, work:, log:, env: ENV)
      @platform = platform
      @packages = packages
      @build_args = build_args
      @host = host
      @runtimes = runtimes
      @work = work
      @log = log
      @env = env
      @ruby = nil # : String?
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
        registrations = reports.map { |report| [report.feature, report.init] }
        [target.name, Linking.target_build(target, reports)]
      end
      Built.new(registrations:, targets: builds, ndk:)
    end

    # Links the shared library an Android app loads, +into+ it, for the
    # target of +build+: the registration unit's C file +registration+ and
    # the extensions' archives, against the runtime's
    # <tt>libfledgeruby.so</tt>, aligned for 16 KB pages as the runtime's
    # own library is, with the NDK's C++ runtime linked statically (a shared one would be a
    # library the package does not carry) when an extension has C++. Returns +into+.
    def shared_library(built, build, registration:, into:)
      ndk = built.ndk or raise Error, "only an Android app links a shared library"
      target = build.target
      cc = target.environment.fetch("FLEDGE_CC")
      cc = "#{cc}++" if build.cxx
      stl = build.cxx ? ["-static-libstdc++"] : [] # : Array[String]
      FileUtils.mkdir_p(File.dirname(into))
      run(clean_env, cc, "-shared", "-fPIC", "-O2", "-I", File.join(target.root, "include"), "-o", into, *stl, "-x", "c", registration, "-x", "none",
        *build.archives, "-L#{target.libdir}", "-lfledgeruby", *build.flags, "-llog", "-lm", "-Wl,-z,max-page-size=16384",
        "-Wl,--exclude-libs,ALL", what: "linking the app's extensions for #{target.name} with #{File.basename(ndk.root)}")
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
    # and the slice's headers, which sit beside its library and not where
    # rbconfig.rb says.
    private def ios_target(slice, root)
      sdk = slice.end_with?("-simulator") ? "iphonesimulator" : "iphoneos"
      arch_dir = rbconfig_dir(root)
      triple = recorded_compiler(arch_dir)[/-target (\S+)/, 1] or raise Error, "#{arch_dir}/rbconfig.rb records no target triple"
      sysroot = xcrun(sdk, "--show-sdk-path")
      environment = {
        "FLEDGE_CC" => "#{xcrun(sdk, '--find', 'clang')} -target #{triple} -isysroot #{sysroot}",
        "FLEDGE_CXX" => "#{xcrun(sdk, '--find', 'clang++')} -target #{triple} -isysroot #{sysroot}",
        "FLEDGE_HEADERS" => File.join(root, "Headers"),
        "FLEDGE_LIBRUBYARG" => "-L#{root} -lfledgeruby -lz $(MAINLIBS) -framework Security -framework CoreFoundation",
      }
      Target.new(name: slice, root:, arch_dir:, libdir: root, environment:, abi: nil)
    end

    # The ABI's tools: the NDK's clang of the very name the runtime was
    # built with, its llvm-ar and llvm-ranlib, and the library that holds
    # Ruby, from the AAR.
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
      }
      Target.new(name: arch, root: tree, arch_dir:, libdir:, environment:, abi:)
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
      package.spec.extensions.each_with_index.map do |extension, index|
        folder = File.dirname(File.join(root, extension))
        init = "Init_fledge_#{first + index}"
        report = File.join(folder, "fledge-report.json")
        env = clean_env.merge(target.environment).merge("FLEDGE_INIT" => init, "FLEDGE_REPORT" => report)
        what = "compiling #{gem}'s extension #{extension} for #{target.name}"
        run(env, ruby, "--disable-gems", "-I", target.arch_dir, "-r", shim_path, File.basename(extension), *args, chdir: folder, what:)
        run(env, "make", "static", chdir: folder, what:)
        describe(JSON.parse(File.read(report)), folder, init, gem, target)
      end
    end

    # What one extension's build came to, from the shim's +reports+ and
    # the Makefile in +folder+.
    private def describe(reports, folder, init, gem, target)
      raise Error, "#{gem}'s extconf.rb called create_makefile #{reports.size} times, and Fledge links one extension for each" if reports.size != 1

      report = reports.first
      archive = File.join(folder, report.fetch("archive"))
      raise Error, "#{gem}'s extension made no #{File.basename(archive)} for #{target.name}" unless File.file?(archive)

      Report.new(
        feature: report.fetch("feature"), init:, archive:, flags: Linking.link_flags(report.fetch("libs"), dir: folder),
        cxx: File.read(File.join(folder, "Makefile")).match?(/^ORIG_SRCS = .*\.(?:cc|cpp|cxx|C)(?:\s|$)/)
      )
    end

    # The gem's files unpacked into +dir+, and the folder its extension
    # paths are relative to.
    private def source_root(package, dir)
      FileUtils.rm_rf(dir)
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
