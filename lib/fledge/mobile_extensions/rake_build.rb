# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

module Fledge
  class MobileExtensions
    # Runs a gem's Rakefile for one target of a phone, as RubyGems runs it.
    #
    # A gem may name a Rakefile (or an <tt>mkrf_conf</tt> script) in its
    # gemspec's +extensions+, and RubyGems then runs Rake there
    # (<tt>Gem::Ext::RakeBuilder</tt>), which may do anything. Most such
    # Rakefiles compile nothing: they install a dependency, or check for a
    # system library. Refusing them all would refuse gems that would run.
    #
    # This class runs RubyGems' own builder under this computer's Ruby,
    # with every Ruby the build starts reading the phone's
    # <tt>rbconfig.rb</tt> (TOOLS, through <tt>RUBYOPT</tt>), as crossenv
    # and cibuildwheel give a Python build the target's sysconfig. A
    # Rakefile that builds nothing gives no extension. A shared library the
    # build leaves in the gem, such as one for Ruby's ffi, is refused by
    # name, since a phone app opens no library at run time.
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
    #   build.call(target, gem, spec, root, "ext/mkrf_conf.rb", [], 0) # => []
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

      # The names of shared libraries: what a build for a phone must not
      # leave behind, since a phone app loads none from a file.
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
      # returns the Report of each extension it built: none. Raises
      # Fledge::Error when the build fails, or leaves a shared library.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   build.call(target, gem, spec, root, "ext/mkrf_conf.rb", [], 0) # => []
      #--
      # SPDX-SnippetEnd
      #++
      def call(target, gem, spec, root, extension, args, _first)
        folder = File.join(@work, target.name, "#{spec.full_name}-rake")
        FileUtils.rm_rf(folder)
        FileUtils.mkdir_p(dest = File.join(folder, "install"))
        before = shared_libraries(root)
        @run.call(environment(target, folder), @ruby, "--disable=rubyopt", write(folder, "build.rb", BUILD), extension, dest,
          File.join(root, File.dirname(extension)), *args, what: "building #{gem}'s extension #{extension} for #{target.name}", chdir: root)
        refuse(gem, extension, target, shared_libraries(root) - before + shared_libraries(dest))
        []
      end

      # The environment of the build for +target+: the phone's
      # rbconfig.rb, and the tools in it, for every Ruby it starts, and
      # this computer's Ruby for <tt>RbConfig.ruby</tt>.
      private def environment(target, folder)
        @environment.merge(target.environment).merge(
          "FLEDGE_RUBY" => @ruby, "RUBY" => @ruby, "RUBYOPT" => "-I#{target.arch_dir} -r#{write(folder, 'phone.rb', TOOLS)}"
        )
      end

      # Refuses the shared libraries in +paths+, naming the first.
      private def refuse(gem, extension, target, paths)
        return if paths.empty?

        raise Error, "#{gem}'s #{File.basename(extension)} linked #{File.basename(paths.first)} for #{target.name}, a shared library. " \
          "A phone app opens no library at run time, so Fledge links in what a gem builds, and does not yet link " \
          "what a Rakefile builds. Leave the gem out of the app's phone build (gem \"#{gem.name}\", platforms: [...] " \
          "in the Gemfile)."
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
