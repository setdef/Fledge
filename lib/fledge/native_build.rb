# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require_relative "binary"
require_relative "compiled_gem"
require_relative "error"
require_relative "git_package"
require_relative "tar_gz"

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
      @runtimes = runtimes
      @work = File.join(work, "native-#{platform}")
      @log = log
      @env = env
      @ruby = nil # : String?
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
      results = run(jobs.map { |job| job[2] })
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

    # Runs SCRIPT on the runtime's Ruby for +jobs+, and returns where each
    # gem and its extensions went.
    private def run(jobs)
      ruby = prepare
      plan = File.join(@work, "plan.json")
      result = File.join(@work, "result.json")
      script = File.join(@work, "build.rb")
      File.write(script, SCRIPT)
      File.write(plan, JSON.generate({ "home" => home, "jobs" => jobs, "result" => result }))
      @log.puts "Compiling native gems for #{platform} with the runtime's Ruby"
      status = Open3.popen2e(child_env, ruby, script, plan) do |_, output, thread|
        output.each_line { |line| @log.puts line }
        thread.value
      end
      raise Error, "a gem's extension did not compile for #{platform}; the compiler's output is above" unless status.success?

      JSON.parse(File.read(result))
    end

    # Unpacks the runtime and its build-only companion, once, and returns
    # the path of the runtime's Ruby.
    private def prepare
      @ruby ||= begin
        ruby = File.join(@work, "ruby")
        FileUtils.rm_rf(ruby)
        [@runtimes.archive(platform), @runtimes.dev_archive(platform)].each do |archive|
          TarGz.each_entry(archive) { |entry| entry.write_into(ruby) unless entry.type == :directory && File.directory?(File.join(ruby, entry.path)) }
        end
        top = Dir.children(ruby).first.to_s
        File.join(ruby, top, *(platform.windows? ? %w[ruby bin ruby.exe] : %w[bin ruby]))
      end
    end

    # The gem folder the runtime's Ruby installs into.
    private def home
      File.join(@work, "gems")
    end

    # The environment the runtime's Ruby and the compiler run in: the
    # caller's, without the developer's Ruby settings, with RubyGems
    # pointed at the build's gem folder, and on macOS the runtime's oldest
    # macOS as the deployment target, which clang and rustc both read.
    private def child_env
      env = @env.to_h.keys.grep(SCRUBBED).to_h { |name| [name, nil] } # : Hash[String, String?]
      env["GEM_HOME"] = home
      env["GEM_PATH"] = home
      minimum = platform.macos_minimum
      env["MACOSX_DEPLOYMENT_TARGET"] = minimum if minimum
      env
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
        build_info: File.file?(build_info) ? File.read(build_info) : nil, problems: floor_problems(gem, built + extensions),
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

    # Why a compiled file would not load on the oldest system the runtime
    # runs on: a newer macOS than it, or a newer glibc, which a compiler
    # targets when it builds on a newer computer.
    private def floor_problems(gem, entries)
      macos = platform.macos_minimum
      glibc = platform.glibc_minimum
      entries.filter_map do |entry|
        bytes = (entry.type == :file) ? entry.content.to_s : ""
        if macos && (found = Binary.macos_minimum(bytes)) && newer?(found, macos)
          "#{gem}'s #{entry.path} needs macOS #{found}, and apps for #{platform} run on macOS #{macos} and later. Compile it " \
            "with MACOSX_DEPLOYMENT_TARGET=#{macos}, which Fledge sets, so check its extconf.rb does not override it."
        elsif glibc && (found = Binary.glibc_minimum(bytes)) && newer?(found, glibc)
          "#{gem}'s #{entry.path} needs glibc #{found}, and apps for #{platform} run on glibc #{glibc} and later. Build on a " \
            "Linux with glibc #{glibc}, such as Ubuntu 24.04."
        end
      end
    end

    private def newer?(found, floor)
      Gem::Version.new(found) > Gem::Version.new(floor)
    end
  end
end
