# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "fileutils"
require "json"
require_relative "ffi_library"

module Fledge
  class MobileExtensions
    # Runs a gem's Rakefile for one target of a phone, as RubyGems runs it,
    # and links in the extensions it builds with mkmf.
    #
    # A gem may name a Rakefile (or an <tt>mkrf_conf</tt> script) in its
    # gemspec's +extensions+, and RubyGems then runs Rake there
    # (<tt>Gem::Ext::RakeBuilder</tt>), which may do anything. Most such
    # Rakefiles compile nothing: they install a dependency, or check for a
    # system library. A few, digest-crc's among them, run an
    # <tt>extconf.rb</tt> and +make+ for each extension, which on a phone
    # would make a shared library no phone loads.
    #
    # This class runs RubyGems' own builder under this computer's Ruby,
    # with every Ruby the build starts reading the phone's
    # <tt>rbconfig.rb</tt> (TOOLS, through <tt>RUBYOPT</tt>), as crossenv
    # and cibuildwheel give a Python build the target's sysconfig. Each
    # <tt>create_makefile</tt> the build calls is mkmf's, aimed at the
    # phone as an <tt>extconf.rb</tt> is
    # (doc/contributors/design/phone-projects.md, "Gems with
    # extensions"), with its Init function renamed and a line in a
    # report (HOOK). Once the build is done, it
    # runs mkmf's <tt>make static</tt> in each folder the report names, and
    # names each extension by its folder's place in the gem's require
    # paths. A Rakefile that builds nothing gives no extension. The gems
    # the gem depends on are on the load path of every Ruby the build
    # starts, compiled for this computer where they have an extension
    # (HostGems), as ffi-compiler needs ffi.
    #
    # Any other shared library the build writes or changes in the gem,
    # such as one ffi-compiler links for Ruby's ffi to open, is an
    # FfiLibrary, once BuiltFor finds it built for the target; one built
    # for anything else is refused by name. The libraries are compared by
    # their bytes before and after the build, since a package may hold a
    # library at the very path the build writes, as llhttp-ffi 0.5.1's
    # holds one its author built on a Mac. A library the package holds
    # that the build leaves as it was is an FfiLibrary too when it is
    # built for the target, since the gem opens it on the phone as a
    # desktop's gem opens the one its package holds for that desktop; one
    # built for the desktop that the phone is to Ruby's ffi is refused,
    # since the gem would ask <tt>dlopen</tt> for it on the phone; and
    # any other stays the gem's own file.
    #
    # Use it from Fledge::MobileExtensions, once for each target and each
    # extension Rake builds.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   build = Fledge::MobileExtensions::RakeBuild.new(ruby:, work:, environment: {}, run: method(:run), load_path: [],
    #     built_for: Fledge::MobileExtensions::BuiltFor.new(ndk: nil))
    #   build.call(target, gem, spec, root, "ext/digest/Rakefile", [], 0).first.feature
    #   # => "digest/crc12_3gpp/crc12_3gpp_ext"
    #--
    # SPDX-SnippetEnd
    #++
    class RakeBuild
      # What this computer's Ruby runs, given the extension's path in the
      # gem, the folder to install into, the extension's folder, and the
      # gem's build options: RubyGems' own builder for the extension.
      BUILD = <<~RUBY
        require "rubygems/ext"
        extension, dest, dir, *args = ARGV
        results = []
        begin
          Gem::Ext::Builder.allocate.builder_for(extension).build(extension, dest, results, args, nil, dir)
          puts results
        rescue Gem::InstallError, Gem::Ext::BuildError => e
          puts results, e.message
          exit 1
        end
      RUBY

      # What every Ruby the build starts loads after TOOLS: mkmf's
      # <tt>create_makefile</tt>, whenever mkmf is loaded, made to write
      # the static archive's rule beside the shared library's, which the
      # Rakefile's own +make+ still builds (mkmf writes the rule when
      # <tt>$static</tt> is not +nil+, and <tt>false</tt> leaves the shared
      # link as it is), to rename the extension's Init function, as Ruby's
      # <tt>ext/extmk.rb</tt> does (through <tt>$CPPFLAGS</tt>, as SHIM
      # does), and to report where it ran. On iOS
      # that shared link names no Ruby, since mkmf links an extension of a
      # static Ruby against none, so it looks Ruby's functions up when
      # loaded (<tt>-undefined dynamic_lookup</tt>, as a Mac's static Ruby
      # links its extensions). No phone loads it: only the static archive
      # goes into the app.
      HOOK = <<~'RUBY'
        module FledgeStaticExtension
          def create_makefile(target, *rest, &block)
            require "json"
            $static = false
            $DLDFLAGS << " -undefined dynamic_lookup" if RbConfig::CONFIG["target_os"].start_with?("darwin")
            name = File.basename(target)
            $CPPFLAGS << " -DInit_#{name}=#{ENV.fetch('FLEDGE_INIT_PREFIX')}#{name}"
            result = super
            report = { "target" => target, "dir" => Dir.pwd, "libs" => $libs,
                       "archive" => "#{name}.#{CONFIG['LIBEXT']}", "library" => "#{name}.#{CONFIG['DLEXT']}" }
            File.open(ENV.fetch("FLEDGE_REPORT"), "a") { |file| file.puts(JSON.generate(report)) }
            result
          end
        end
        module MakeMakefile
          prepend FledgeStaticExtension
        end
      RUBY

      # The names of shared libraries: the extensions mkmf built, which
      # are linked into the app instead, and any other a build leaves,
      # which is a library for Ruby's ffi (FfiLibrary) or refused.
      SHARED = /\.(?:so|bundle|dylib)(?:\.\d+)*\z/

      # The debug symbols Apple's linker writes beside a shared library
      # (<tt>NAME.bundle.dSYM/Contents/Resources/DWARF/NAME.bundle</tt>),
      # which are not one.
      DEBUG = %r{\.dSYM/}

      # Creates the builder.
      #
      # [ruby] This computer's runtime's Ruby.
      # [work] A folder of the build's own.
      # [environment] The environment every command starts from, with the
      #               developer's toolchain variables removed.
      # [run] What runs a command: called with the environment, the
      #       command, <tt>what:</tt>, and <tt>chdir:</tt>, it raises
      #       Fledge::Error when the command fails.
      # [load_path] The folders of the code of the gems the gem depends
      #             on, for this computer (HostGems#load_path).
      # [built_for] The BuiltFor that reads what each library left is
      #             built for.
      def initialize(ruby:, work:, environment:, run:, load_path:, built_for:)
        @ruby = ruby
        @work = work
        @environment = environment
        @run = run
        @load_path = load_path
        @built_for = built_for
      end

      # Runs the Rakefile +extension+, a path in +spec+'s gem, unpacked at
      # +root+, for +target+ with the gem's build options +args+, and
      # returns a Report for each extension it built with mkmf, its Init
      # function named <tt>Init_fledge_FIRST_NAME</tt>, and an FfiLibrary,
      # with no links yet, for each other shared library it wrote or
      # changed in the gem, and each the package held built for
      # +target+. Raises Fledge::Error when the build fails, or
      # leaves a shared library in DEST, one not built for +target+, or
      # one of the package's built for the desktop the phone is to ffi.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   build.call(target, gem, spec, root, "ext/digest/Rakefile", [], 0).first.init
      #   # => "Init_fledge_0_crc12_3gpp_ext"
      #--
      # SPDX-SnippetEnd
      #++
      def call(target, gem, spec, root, extension, args, first)
        folder = File.join(@work, target.name, "#{spec.full_name}-rake")
        FileUtils.rm_rf(folder)
        FileUtils.mkdir_p(dest = File.join(folder, "install"))
        report = File.join(folder, "extensions.jsonl")
        before = shared_libraries(root)
        what = "building #{gem}'s extension #{extension} for #{target.name}"
        env = environment(target, folder, report, first)
        @run.call(env, @ruby, "--disable=rubyopt", write(folder, "build.rb", BUILD), extension, dest, File.join(root, File.dirname(extension)),
          *args, what:, chdir: root)
        lines = File.file?(report) ? File.readlines(report) : [] # : Array[String]
        built = lines.map { |line| JSON.parse(line) } # : Array[Hash[String, String]]
        made = built.map { |entry| File.join(entry.fetch("dir"), entry.fetch("library")) }
        refuse(gem, extension, target, shared_libraries(dest).keys)
        libraries = shared_libraries(root).except(*made).filter_map do |path, digest|
          ffi_library(gem, extension, target, path.delete_prefix("#{File.realpath(root)}/"), path, held: before[path] == digest)
        end
        places = spec.require_paths.reject { |path| File.absolute_path?(path) }.map { |path| File.join(root, path) }
          .select { |path| File.directory?(path) }.map { |path| File.realpath(path) }
        [*built.map { |entry| describe(entry, env, places, gem, target, what) }, *libraries]
      end

      # The environment of the build for +target+: the phone's
      # rbconfig.rb, the gem's dependencies, the tools in it, and the
      # hook, for every Ruby it starts, and this computer's Ruby for
      # <tt>RbConfig.ruby</tt>.
      private def environment(target, folder, report, first)
        includes = [target.arch_dir, *@load_path].map { |path| "-I#{path}" }.join(" ")
        @environment.merge(target.environment).merge(
          "FLEDGE_INIT_PREFIX" => "Init_fledge_#{first}_", "FLEDGE_REPORT" => report, "FLEDGE_RUBY" => @ruby, "RUBY" => @ruby,
          "RUBYOPT" => "#{includes} -r#{write(folder, 'phone.rb', TOOLS + HOOK)}"
        )
      end

      # Refuses the shared libraries in +paths+, which the build installed
      # into DEST, naming the first.
      private def refuse(gem, extension, target, paths)
        return if paths.empty?

        raise Error, "#{gem}'s #{File.basename(extension)} installed #{File.basename(paths.first)} for #{target.name}, a shared library " \
          "that is not an extension mkmf built. Fledge links in the extensions a Rakefile builds with mkmf, and ships the " \
          "other libraries it builds where it leaves them in the gem, not what it installs. #{advice(gem, target)}"
      end

      # The FfiLibrary for the shared library at +path+, +file+ in the gem,
      # which the build wrote or changed, or which the package held
      # (+held+) built for +target+; or +nil+ for one the package held
      # built for another phone's or ABI's system, which stays one of the
      # gem's files. Raises Fledge::Error for a library the build made
      # for another system than +target+, or one the package held built
      # for the desktop the phone is to Ruby's ffi.
      private def ffi_library(gem, extension, target, file, path, held:)
        system = @built_for.call(target, path)
        wanted = @built_for.wanted(target)
        return FfiLibrary.new(gem: gem.name, file:, path:, links: []) if system == wanted
        if held
          return nil unless @built_for.desktop?(target, system)

          raise Error, "#{gem}'s #{File.basename(extension)} left #{file} built for #{system}, not #{wanted} (#{target.name}): the " \
            "gem's package holds it, and its build did not replace it, so the gem would load a library for another system. " \
            "Fledge ships only libraries built for the phone. #{advice(gem, target)}"
        end

        raise Error, "#{gem}'s #{File.basename(extension)} built #{file} for #{system}, not #{wanted} (#{target.name}). Fledge ships " \
          "a library a Rakefile builds when it is built for the phone, with the compiler Fledge gives the build in CC. " \
          "#{advice(gem, target)}"
      end

      # What to do about +gem+ for the phone of +target+.
      private def advice(gem, target)
        "Leave the gem out of the app's #{target.abi ? 'android' : 'ios'} build (gem \"#{gem.name}\", platforms: [...] in the Gemfile)."
      end

      # The Report for one extension the build made with mkmf: its static
      # archive, made with <tt>make static</tt> in its folder, and its
      # name, its folder's path in the first of +places+ that holds it,
      # or else the target create_makefile was given.
      private def describe(entry, env, places, gem, target, what)
        dir = entry.fetch("dir")
        @run.call(env, "make", "static", what:, chdir: dir)
        archive = File.join(dir, entry.fetch("archive"))
        raise Error, "#{gem}'s extension made no #{File.basename(archive)} for #{target.name}" unless File.file?(archive)

        name = File.basename(entry.fetch("target"))
        place = places.find { |path| "#{dir}/".start_with?("#{path}/") }
        feature = place ? File.join(dir.delete_prefix(place).delete_prefix("/"), name).delete_prefix("/") : entry.fetch("target")
        libs = "#{entry.fetch('libs')} #{Linking.local_libs(env, dir)}"
        Report.new(
          feature:, init: "#{env.fetch('FLEDGE_INIT_PREFIX')}#{name}", archive:, flags: Linking.link_flags(libs, dir:),
          cxx: File.read(File.join(dir, "Makefile")).match?(/^ORIG_SRCS = .*\.(?:cc|cpp|cxx|C)(?:\s|$)/) || Linking.cxx_runtime?(libs)
        )
      end

      # The shared libraries in +folder+, by their real paths, each with
      # the SHA-256 of its bytes.
      private def shared_libraries(folder)
        Dir.glob("**/*", base: folder).grep(SHARED).grep_v(DEBUG).map { |path| File.join(folder, path) }
          .select { |path| File.file?(path) }.to_h { |path| [File.realpath(path), Digest::SHA256.file(path).hexdigest] }
      end

      private def write(folder, name, text)
        path = File.join(folder, name)
        File.write(path, text)
        path
      end
    end
  end
end
