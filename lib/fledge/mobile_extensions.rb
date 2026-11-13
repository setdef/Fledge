# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "archive"
require_relative "entry"
require_relative "error"
require_relative "mobile_extensions/android_library"
require_relative "mobile_extensions/extconf_build"
require_relative "mobile_extensions/library"
require_relative "mobile_extensions/linking"
require_relative "mobile_extensions/ndk"
require_relative "mobile_extensions/rake_build"
require_relative "mobile_extensions/runner"
require_relative "mobile_extensions/sources"
require_relative "mobile_extensions/stub"
require_relative "mobile_extensions/targets"

module Fledge
  # Compiles an app's gems' C, C++, and Rust extensions for a phone (ADR 022).
  #
  # A phone's Ruby loads no extension from a file (ADR 079), so
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
  # rb_sys, on its load path. Where a desktop's RubyGems leaves the file
  # of each extension an <tt>extconf.rb</tt> builds, in the gem's own
  # require path, it writes a Ruby file that requires the linked one
  # (Stub), so that a <tt>require_relative</tt> of the path finds it.
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
  #   compiler = Fledge::MobileExtensions.new(platform:, packages: { gem => package }, build_args: {}, host:, runtimes:, work:,
  #     log: $stderr, gem_dir: "lib/ruby/gems/4.1.0+5")
  #   built = compiler.call(runtime_tree)
  #   built.registrations # => [["adder/adder", "Init_fledge_0"]]
  #   built.targets.keys  # => ["ios-arm64", "ios-arm64-simulator"]
  #   built.stubs.map(&:path) # => ["app/gems/adder/lib/adder/adder.rb"]
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
    #
    # And the folders of the computer that built the runtime taken out of
    # its flags and its configure options. That build gave Ruby's
    # configure its OpenSSL, libyaml, and libffi as
    # <tt>--with-NAME-dir</tt> options, and libffi's headers and library
    # in +CPPFLAGS+ and +LDFLAGS+ (<tt>tasks/runtime_builder/mobile.rb</tt>,
    # <tt>ios.rb</tt>, and <tt>android.rb</tt>), and <tt>rbconfig.rb</tt>
    # records them all; mkmf starts <tt>$CPPFLAGS</tt>, <tt>$LDFLAGS</tt>,
    # and <tt>$DLDFLAGS</tt> from them, compiles and links each of its
    # checks with them (+TRY_LINK+), and reads the options as the
    # extension's own, so <tt>dir_config("openssl")</tt> takes that
    # folder (<tt>lib/mkmf.rb</tt>, lines 110, 1895, 2778, and 2957 at
    # Ruby 4.1.0-preview1). On a computer where those folders still are,
    # as where the runtime was built, the ffi gem's
    # <tt>have_library("ffi")</tt> found the runtime's own libffi, which
    # the app's link, with no such folder, could not find
    # (<tt>unable to find library -lffi</tt>); everywhere else they name
    # nothing. A folder in the runtime itself is kept, and so are the
    # developer's own options for a gem, which reach mkmf as arguments.
    TOOLS = <<~'RUBY'
      require "rbconfig"
      require "shellwords"
      top = RbConfig::TOPDIR
      outside = ->(path) { path.start_with?("/") && !(top && path.start_with?("#{top}/")) }
      [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].each do |config|
        %w[CPPFLAGS CFLAGS CXXFLAGS LDFLAGS DLDFLAGS].each do |key|
          next unless config[key]

          config[key] = config[key].gsub(/(?<=\A|\s)-(?:I|L|F|isystem)\s*(\/\S*)\s*/) { |flag| outside[$1] ? "" : flag }
        end
        config["configure_args"] = config["configure_args"].to_s.shellsplit.reject do |arg|
          name, value = arg.split("=", 2)
          value && name.match?(/\A--with-[\w-]+-(?:dir|include|lib)\z/) && outside[value]
        end.shelljoin
      end
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
    #
    # With +FLEDGE_SHARED+ set, mkmf makes the shared object a desktop's
    # does instead (Library), its Init function its own, linked against
    # +FLEDGE_LIBRUBYARG+, which mkmf leaves out for a Ruby with no shared
    # libruby (<tt>init_mkmf</tt>, line 2804), with +FLEDGE_DLDFLAGS+
    # added to its link and +FLEDGE_LDSHAREDXX+, when set, linking C++:
    # an extension with C++ sources, and one whose <tt>extconf.rb</tt>
    # names a desktop's C++ runtime (<tt>-lc++</tt>, <tt>-lstdc++</tt>),
    # which the NDK would link as <tt>libc++_shared.so</tt>, a library the
    # package does not carry (Linking.cxx_runtime?).
    SHIM = TOOLS + <<~'RUBY'
      require "json"
      shared = ENV.key?("FLEDGE_SHARED")
      if shared && ENV.key?("FLEDGE_LDSHAREDXX")
        [RbConfig::CONFIG, RbConfig::MAKEFILE_CONFIG].each { |config| config["LDSHAREDXX"] = ENV.fetch("FLEDGE_LDSHAREDXX").dup }
      end
      require "mkmf"
      if shared
        $LIBRUBYARG = ENV.fetch("FLEDGE_LIBRUBYARG").dup
        $DLDFLAGS << " #{ENV.fetch('FLEDGE_DLDFLAGS', '')}"
      else
        $static = true
      end
      module MakeMakefile
        alias_method :fledge_create_makefile, :create_makefile
        def create_makefile(target, *rest, &block)
          shared = ENV.key?("FLEDGE_SHARED")
          $CPPFLAGS << " -DInit_#{File.basename(target)}=#{ENV.fetch('FLEDGE_INIT')}" unless shared
          if shared && ENV.key?("FLEDGE_LDSHAREDXX") && $libs.match?(/(?:\A|\s)-l(?:c\+\+|stdc\+\+)(?=\s|\z)/)
            $libs = $libs.gsub(/(?:\A|\s)-l(?:c\+\+|stdc\+\+)(?=\s|\z)/, "")
            CONFIG["LDSHARED"] = CONFIG["LDSHAREDXX"]
          end
          result = fledge_create_makefile(target, *rest, &block)
          reports = File.exist?(ENV.fetch("FLEDGE_REPORT")) ? JSON.parse(File.read(ENV.fetch("FLEDGE_REPORT"))) : []
          reports << {
            "feature" => target, "archive" => "#{File.basename(target)}.#{CONFIG[shared ? 'DLEXT' : 'LIBEXT']}",
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
    class TargetBuild < Data.define(:target, :archives, :flags, :cxx, :libraries)
      ##
      # :attr_reader: target
      # The Target compiled for.

      ##
      # :attr_reader: libraries
      # The Library of each extension built as a file, which Ruby loads
      # from it rather than from the app's linked code.

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

    # What #call returns: the extensions to register, as pairs of the name
    # <tt>require</tt> asks for and the function that initializes it (the
    # same for every target), what each target compiled to, and the files
    # that stand where a desktop has an extension's file (Stub).
    class Built < Data.define(:registrations, :targets, :ndk, :stubs)
      ##
      # :attr_reader: registrations
      # Pairs of the feature (<tt>"adder/adder"</tt>) and its renamed Init function.

      ##
      # :attr_reader: targets
      # Each target's TargetBuild, by the target's name.

      ##
      # :attr_reader: ndk
      # The NDK::NDK that compiled them, for Android; +nil+ for iOS.

      ##
      # :attr_reader: stubs
      # The Entry of each file Stub writes, with paths relative to the
      # app's Ruby root, as the gems' entries are.
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
    # [gem_dir] The runtime's gem folder, relative to the app's Ruby root,
    #           where the gems' entries install them (Built#stubs).
    # [env] The environment to start from (default: +ENV+).
    # [dependencies] The packages of the gems those gems depend on, by
    #                gem (default: none), whose code an extconf.rb may
    #                require, as rb-sys's is.
    # [files] Whether to build each C or C++ extension an
    #         <tt>extconf.rb</tt> builds for Android as a file Ruby loads,
    #         a Library, as on a desktop, rather than to link it in
    #         (default: +false+).
    def initialize(platform:, packages:, build_args:, host:, runtimes:, work:, log:, gem_dir:, env: ENV, dependencies: {}, files: false)
      @platform = platform
      @files = files
      @gem_dir = gem_dir
      @packages = packages
      @dependencies = dependencies
      @build_args = build_args
      @host = host
      @runtimes = runtimes
      @work = work
      @env = env
      @runner = Runner.new(log:, env:)
      @ruby = nil # : String?
      @rake_build = nil # : RakeBuild?
      @extconf_build = nil # : ExtconfBuild?
      @load_path = nil # : Array[String]?
      @stubs = {} # : Hash[String, Entry]
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
      ndk = (@platform.name == "android") ? NDK.find(@env, host: @host) : nil
      registrations = [] # : Array[[String, String]]
      @stubs = {} # : Hash[String, Entry]
      builds = Targets.new(work: @work).call(tree, ndk).to_h do |target|
        built = compile_target(target)
        libraries = built.grep(Library) # : Array[Library]
        reports = built.grep(Report) # : Array[Report]
        registrations = same_registrations(registrations, reports)
        [target.name, Linking.target_build(target, reports, libraries:)]
      end
      same_files(builds.values)
      refuse_clash(registrations)
      Built.new(registrations:, targets: builds, ndk:, stubs: @stubs.values)
    end

    # Links the shared library an Android app loads, +into+ it, for the
    # target of +build+, one of +built+'s, with the registration unit's C
    # file +registration+ (AndroidLibrary). Returns +into+.
    def shared_library(built, build, registration:, into:)
      AndroidLibrary.new(runner: @runner).call(built, build, registration:, into:)
    end

    # Compiles every gem's extensions for +target+, and returns a Report
    # for each, their Init functions numbered from 0, or a Library for
    # each built as a file.
    private def compile_target(target)
      reports = [] # : Array[Report | Library]
      @packages.each do |gem, package|
        reports.concat(compile(target, gem, package, @build_args.fetch(gem.name, []), reports.size)) if package.extensions?
      end
      reports
    end

    # The registrations of +reports+, one target's, once they are the
    # same as +registrations+, the targets' before, if there were any.
    private def same_registrations(registrations, reports)
      found = reports.map { |report| [report.feature, report.init] } # : Array[[String, String]]
      return found if registrations.empty? || found == registrations

      raise Error, "the app's gems built different extensions for each target of #{@platform}: #{registrations.to_h.keys} and #{found.to_h.keys}"
    end

    # Refuses +builds+ whose targets built different extensions as files.
    private def same_files(builds)
      features = builds.map { |build| build.libraries.map(&:feature) }.uniq
      return if features.size <= 1

      raise Error, "the app's gems built different extensions for each target of #{@platform}: #{features.map(&:inspect).join(' and ')}"
    end

    # Refuses two of +registrations+ with one Init function, which one app
    # cannot link.
    private def refuse_clash(registrations)
      clash = registrations.group_by(&:last).values.find { |pairs| pairs.size > 1 } or return

      raise Error, "The extensions #{clash.map(&:first).join(' and ')} both start with #{clash.first.last}, and one app can link only one"
    end

    # Compiles +package+'s extensions for +target+, in a folder of their
    # own, and returns a report for each: the archive, its flags, the
    # feature, and its Init function, numbered from +first+.
    private def compile(target, gem, package, args, first)
      root = Sources.unpack(package, File.join(@work, target.name, package.spec.full_name))
      reports = [] # : Array[Report | Library]
      package.spec.extensions.each do |extension|
        number = first + reports.size
        next reports.concat(rake_build.call(target, gem, package.spec, root, extension, args, number)) if self.class.rake?(extension)

        reports << extconf(target, gem, package, root, extension, args, number)
      end
      reports
    end

    # Compiles the extension the <tt>extconf.rb</tt> at +extension+, a
    # path in +package+'s gem unpacked at +root+, builds (ExtconfBuild),
    # with Cargo when the gem depends on rb_sys, and keeps the Stub that
    # stands where a desktop has its file. Returns its Report; or, built
    # as a file (+files+, for Android, and not Rust), its Library, with
    # the paths where a desktop has its file, and no Stub.
    private def extconf(target, gem, package, root, extension, args, number)
      rust = package.spec.runtime_dependencies.any? { |dependency| dependency.name == "rb_sys" }
      shared = @files && !target.abi.nil? && !rust
      report = extconf_build.call(target, gem, File.dirname(File.join(root, extension)), File.basename(extension), args, number, rust:, shared:)
      if report.is_a?(Library)
        return report.with(links: Library.links(package, report.feature, platform: target.name, gem_dir: @gem_dir))
      end

      stub = Stub.for(package, report.feature, root:, gem_dir: @gem_dir)
      @stubs[stub.path] = stub if stub
      report
    end

    # The builder of extensions an <tt>extconf.rb</tt> builds
    # (ExtconfBuild), with the gems its gem depends on on its load path.
    private def extconf_build
      @extconf_build ||= ExtconfBuild.new(ruby:, work: @work, load_path:, environment: @runner.clean_env, run: @runner)
    end

    # The builder of extensions a Rakefile builds (RakeBuild).
    private def rake_build
      @rake_build ||= RakeBuild.new(ruby:, work: @work, environment: @runner.clean_env, run: @runner)
    end

    # The folders of the code of the gems the compiled gems depend on,
    # unpacked once, for each extconf.rb's load path.
    private def load_path
      @load_path ||= @dependencies.values.flat_map do |package|
        root = Sources.unpack(package, File.join(@work, "dependencies", package.spec.full_name))
        package.spec.require_paths.map { |path| File.expand_path(path, root) }
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
  end
end
