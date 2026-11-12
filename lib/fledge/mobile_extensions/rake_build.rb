# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"

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
    # phone as an <tt>extconf.rb</tt> is (ADR 022), with its Init function
    # renamed and a line in a report (HOOK). Once the build is done, it
    # runs mkmf's <tt>make static</tt> in each folder the report names, and
    # names each extension by its folder's place in the gem's require
    # paths. A Rakefile that builds nothing gives no extension. Any other
    # shared library the build leaves, such as one for Ruby's ffi, is
    # refused by name, since a phone app opens no library at run time.
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
    #   build = Fledge::MobileExtensions::RakeBuild.new(ruby:, work:, environment: {}, run: method(:run))
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
            report = { "target" => target, "dir" => Dir.pwd, "libs" => [$libs, $LOCAL_LIBS].join(" "),
                       "archive" => "#{name}.#{CONFIG['LIBEXT']}", "library" => "#{name}.#{CONFIG['DLEXT']}" }
            File.open(ENV.fetch("FLEDGE_REPORT"), "a") { |file| file.puts(JSON.generate(report)) }
            result
          end
        end
        module MakeMakefile
          prepend FledgeStaticExtension
        end
      RUBY

      # The names of shared libraries: what a build for a phone must not
      # leave behind, but for the extensions mkmf built, since a phone app
      # loads none from a file.
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
      def initialize(ruby:, work:, environment:, run:)
        @ruby = ruby
        @work = work
        @environment = environment
        @run = run
      end

      # Runs the Rakefile +extension+, a path in +spec+'s gem, unpacked at
      # +root+, for +target+ with the gem's build options +args+, and
      # returns a Report for each extension it built with mkmf, its Init
      # function named <tt>Init_fledge_FIRST_NAME</tt>. Raises
      # Fledge::Error when the build fails, or leaves a shared library
      # that is not one of those extensions.
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
        refuse(gem, extension, target, shared_libraries(root) - before - made + shared_libraries(dest))
        places = spec.require_paths.reject { |path| File.absolute_path?(path) }.map { |path| File.join(root, path) }
          .select { |path| File.directory?(path) }.map { |path| File.realpath(path) }
        built.map { |entry| describe(entry, env, places, gem, target, what) }
      end

      # The environment of the build for +target+: the phone's
      # rbconfig.rb, the tools in it, and the hook, for every Ruby it
      # starts, and this computer's Ruby for <tt>RbConfig.ruby</tt>.
      private def environment(target, folder, report, first)
        @environment.merge(target.environment).merge(
          "FLEDGE_INIT_PREFIX" => "Init_fledge_#{first}_", "FLEDGE_REPORT" => report, "FLEDGE_RUBY" => @ruby, "RUBY" => @ruby,
          "RUBYOPT" => "-I#{target.arch_dir} -r#{write(folder, 'phone.rb', TOOLS + HOOK)}"
        )
      end

      # Refuses the shared libraries in +paths+, naming the first.
      private def refuse(gem, extension, target, paths)
        return if paths.empty?

        raise Error, "#{gem}'s #{File.basename(extension)} linked #{File.basename(paths.first)} for #{target.name}, a shared library " \
          "that is not an extension mkmf built, as a library for Ruby's ffi is not. A phone app opens no library at " \
          "run time, so Fledge links in the extensions a Rakefile builds with mkmf, and nothing else. Leave the gem " \
          "out of the app's phone build (gem \"#{gem.name}\", platforms: [...] in the Gemfile)."
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
        libs = entry.fetch("libs")
        Report.new(
          feature:, init: "#{env.fetch('FLEDGE_INIT_PREFIX')}#{name}", archive:, flags: Linking.link_flags(libs, dir:),
          cxx: File.read(File.join(dir, "Makefile")).match?(/^ORIG_SRCS = .*\.(?:cc|cpp|cxx|C)(?:\s|$)/) || Linking.cxx_runtime?(libs)
        )
      end

      private def shared_libraries(folder)
        Dir.glob("**/*", base: folder).grep(SHARED).grep_v(DEBUG).map { |path| File.join(folder, path) }
          .select { |path| File.file?(path) }.map { |path| File.realpath(path) }
      end

      private def write(folder, name, text)
        path = File.join(folder, name)
        File.write(path, text)
        path
      end
    end
  end
end
