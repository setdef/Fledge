# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "binary"
require_relative "compiled_gem"
require_relative "error"
require_relative "git_package"
require_relative "tar_gz"
require_relative "native_build/floors"
require_relative "native_build/runtime_ruby"

module Fledge
  # Compiles an app's native gems for the platform Fledge runs on, against
  # the runtime's own Ruby.
  #
  # A gem that publishes only its source, or that comes from git, has an
  # extension to compile before it can load. The compiled file must suit
  # the Ruby that loads it, which in a built app is the runtime's, not the
  # developer's: its headers, its RbConfig, its ABI. And a compiler builds
  # for the computer it runs on, so Fledge compiles a gem only for the
  # platform it runs on, as <tt>gem install</tt> does, and leaves
  # cross-compiling to later work (ADR 006).
  #
  # This class unpacks the runtime and its build-only companion
  # (Fledge::Runtimes#dev_archive: Ruby's headers, and on Windows its
  # import library) into the build's work folder, and runs the runtime's
  # own Ruby, with none of the developer's Ruby settings, to install each
  # gem as RubyGems installs one (Gem::Installer, with the options
  # <tt>bundle config build.NAME</tt> gives) into a gem folder of its own,
  # after the gems it depends on, which its extconf.rb may require; a git
  # gem's extensions are built in its checkout into Bundler's own
  # extensions folder, as Bundler builds them. The compiler is the
  # developer's: Xcode's command line tools on macOS (with the runtime's
  # oldest macOS as the deployment target), the C compiler on Linux (whose
  # glibc must be no newer than the runtime's oldest, 2.39),
  # MSYS2's UCRT64 toolchain on Windows, found as RubyInstaller finds it
  # for <tt>gem install</tt>, and cargo for a Rust extension. Then it
  # returns each compiled gem as a Fledge::CompiledGem, with anything it
  # compiled that needs a newer macOS or glibc than the runtime's oldest.
  #
  # Use it in <tt>fledge build</tt> when a target is the platform Fledge
  # runs on.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   build = Fledge::NativeBuild.new(platform: Fledge::Platform.local, runtimes: Fledge::Runtimes.new, work: Dir.mktmpdir, log: $stderr)
  #   build.call({ redcarpet => Fledge::GemPackage.new("redcarpet-3.6.1.gem") }, build_args: {})
  #   # => {redcarpet => #<Fledge::CompiledGem ...>}
  #--
  # SPDX-SnippetEnd
  #++
  class NativeBuild
    # The environment variables of the developer's own Ruby, which must not
    # reach the runtime's Ruby: those the launcher hides from an app's boot
    # (runtime/launcher/scrub.c).
    SCRUBBED = /\A(?:RUBY|GEM_|BUNDLE_|BUNDLER_)|\A(?:GEMRC|RI_FORCE_PATH_FOR_DLL)\z/i

    # What the runtime's Ruby runs, given the path of a plan: install each
    # gem as Gem::Installer#install does, or for a git gem build its
    # extensions where Bundler keeps them (Bundler::Source::Git, whose
    # extension folder Bundler's Gem::Specification#extension_dir names
    # [scope, folder].uniq.join("-")), then write where each went. On
    # Windows, it first puts MSYS2's tools on PATH as RubyInstaller's own
    # operating_system.rb does before it installs a gem with extensions.
    SCRIPT = <<~RUBY
      require "json"
      require "rubygems/installer"
      require "rubygems/ext"
      plan = JSON.parse(File.read(ARGV.fetch(0)))
      home = plan.fetch("home")
      if Gem.win_platform?
        require "ruby_installer/runtime"
        RubyInstaller::Runtime.enable_msys_apps(for_gem_install: true)
      end
      results = plan.fetch("jobs").map do |job|
        if job["gem"]
          spec = Gem::Installer.at(job.fetch("gem"), install_dir: home, bin_dir: File.join(home, "bin"), ignore_dependencies: true,
            document: [], build_args: job.fetch("build_args"), wrappers: true, env_shebang: false, force: true).install
        else
          spec = Gem::Specification.load(job.fetch("gemspec"))
          spec.full_gem_path = File.dirname(job.fetch("gemspec"))
          extensions = File.join(home, "bundler", "gems", "extensions", Gem::Platform.local.to_s, Gem.extension_api_version)
          spec.extension_dir = File.join(extensions, [job.fetch("scope"), File.basename(spec.full_gem_path)].uniq.join("-"))
          Gem::Ext::Builder.new(spec, job.fetch("build_args")).build_extensions
        end
        { "gem_dir" => spec.full_gem_path, "extension_dir" => spec.extension_dir }
      end
      File.write(plan.fetch("result"), JSON.generate(results))
    RUBY

    # The files RubyGems writes into an extension's folder that only a
    # person reading why a build failed needs, and which hold the build
    # machine's paths.
    LOGS = %w[gem_make.out mkmf.log].freeze

    # The platform this build compiles for, which is the one Fledge runs
    # on.
    attr_reader :platform

    # Creates the build.
    #
    # [platform] The Fledge::Platform Fledge runs on.
    # [runtimes] The Fledge::Runtimes that finds the runtime and its
    #            build-only companion.
    # [work] The build's own folder, which the caller removes.
    # [log] Where the compiler's output goes, such as <tt>$stderr</tt>.
    # [env] The environment to start from (default: +ENV+).
    def initialize(platform:, runtimes:, work:, log:, env: ENV)
      @platform = platform
      @work = File.join(work, "native-#{platform}")
      @runtime_ruby = RuntimeRuby.new(platform:, runtimes:, work: @work, log:, env:)
    end

    # Compiles each of +packages+ (Fledge::GemPackage or Fledge::GitPackage,
    # by gem) with an extension, and returns +packages+ with each compiled
    # one as a Fledge::CompiledGem. +build_args+ holds each gem's build
    # options by its name. Raises Fledge::Error when a gem does not
    # compile, saying which; the compiler's output is in the log.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   build.call(packages, build_args: { "nokogiri" => ["--use-system-libraries"] }).values.grep(Fledge::CompiledGem).size # => 1
    #--
    # SPDX-SnippetEnd
    #++
    def call(packages, build_args:)
      wanted = packages.select { |_, package| package.extensions? }
      return packages if wanted.empty?

      jobs = install_order(packages, wanted).map { |gem| job(gem, packages.fetch(gem), build_args.fetch(gem.name, [])) }
      results = @runtime_ruby.run(jobs.map { |job| job[2] })
      compiled = {} # : Hash[LockedGem | GitGem, CompiledGem]
      jobs.zip(results).each do |(gem, package, _, args), result|
        compiled[gem] = compiled_gem(gem, package, args, result.to_h) if wanted.key?(gem)
      end
      packages.to_h { |gem, package| [gem, compiled.fetch(gem, package)] }
    end

    # The gems to install for the build, each after the gems it depends on:
    # every gem with an extension, and the gems from a gem server that any
    # of them needs, which its extconf.rb may require (rb_sys, or
    # mini_portile2).
    private def install_order(packages, wanted)
      by_name = packages.keys.to_h { |gem| [gem.name, gem] }
      order = [] # : Array[LockedGem | GitGem]
      visit = lambda do |gem|
        next if order.include?(gem)

        packages.fetch(gem).spec.runtime_dependencies.each { |dependency| by_name[dependency.name]&.then { |needed| visit.call(needed) } }
        order << gem
      end
      wanted.each_key { |gem| visit.call(gem) }
      order.reject { |gem| gem.is_a?(GitGem) && !packages.fetch(gem).extensions? }
    end

    # [gem, package, the plan's job for it, its build options].
    private def job(gem, package, args)
      case package
      when GemPackage then [gem, package, { "gem" => package.path, "build_args" => args }, args]
      when GitPackage
        checkout = File.join(home, "bundler", "gems", package.scope)
        unless File.directory?(checkout)
          FileUtils.mkdir_p(File.dirname(checkout))
          FileUtils.cp_r(package.checkout, checkout)
          FileUtils.rm_rf(File.join(checkout, ".git"))
        end
        [gem, package, { "gemspec" => File.join(checkout, package.gemspec), "scope" => package.scope, "build_args" => args }, args]
      else raise Error, "#{gem} is neither a gem from a gem server nor one from git"
      end
    end

    # The gem folder the runtime's Ruby installs into.
    private def home
      @runtime_ruby.home
    end

    # +package+, compiled, with what its build wrote into the gem's folder
    # and its extensions folder.
    private def compiled_gem(gem, package, args, result)
      gem_dir = result.fetch("gem_dir").to_s
      extension_dir = result.fetch("extension_dir").to_s
      built = new_files(package, gem_dir)
      extensions = files_in(extension_dir).reject { |entry| LOGS.include?(entry.path) }
      build_info = File.join(home, "build_info", "#{package.spec.full_name}.info")
      CompiledGem.new(
        package:, built:, extensions:, extension_dir: relative_to_home(extension_dir), build_args: args,
        build_info: File.file?(build_info) ? File.read(build_info) : nil, problems: Floors.problems(gem, built + extensions, platform),
      )
    end

    # The files the build wrote into the gem's require paths, which is
    # where RubyGems puts what an extension installs, beside the gem's own,
    # with paths relative to the gem's folder.
    private def new_files(package, gem_dir)
      own = package.contents
      package.spec.require_paths.flat_map do |folder|
        files_in(File.join(gem_dir, folder)).filter_map do |entry|
          entry.with(path: "#{folder}/#{entry.path}") unless entry.type == :directory || own.key?("#{folder}/#{entry.path}")
        end
      end
    end

    # The entries under +folder+, with paths relative to it.
    private def files_in(folder)
      File.directory?(folder) ? Entry.walk(folder) : []
    end

    private def relative_to_home(path)
      File.expand_path(path).delete_prefix("#{File.expand_path(home)}/")
    end
  end
end
