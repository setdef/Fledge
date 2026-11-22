# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require_relative "../error"
require_relative "ffi_library"
require_relative "linking"
require_relative "rake_build"
require_relative "rust"

module Fledge
  class MobileExtensions
    # Compiles the extension an <tt>extconf.rb</tt> builds, for one target
    # of a phone: it runs the <tt>extconf.rb</tt> with this computer's
    # Ruby, given the phone's <tt>rbconfig.rb</tt> and SHIM, and then
    # mkmf's <tt>make static</tt>, or, for a gem that depends on rb_sys,
    # the goal of rb-sys's Makefile that has Cargo make a static library
    # (Rust::SHIM).
    #
    # Use it from Fledge::MobileExtensions, once for each target and each
    # extension an <tt>extconf.rb</tt> builds.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   build = Fledge::MobileExtensions::ExtconfBuild.new(ruby:, work:, load_path: [], environment: {}, run: runner)
    #   build.call(target, gem, "/work/adder/ext/adder", "extconf.rb", [], 0, rust: false).init # => "Init_fledge_0"
    #--
    # SPDX-SnippetEnd
    #++
    class ExtconfBuild
      # The names of the files a Rust extension's build writes in its
      # folder (Rust::SHIM).
      RUST_FILES = {
        "FLEDGE_RUST_NATIVE_LIBS" => Rust::NATIVE_LIBS, "FLEDGE_RUST_LIBRARY" => Rust::LIBRARY, "FLEDGE_RUST_MAKEFILE" => Rust::MAKEFILE
      }.freeze

      # Creates the builder.
      #
      # [ruby] This computer's runtime's Ruby.
      # [work] A folder of the build's own.
      # [load_path] The folders of the code of the gems the compiled gems
      #             depend on, for each <tt>extconf.rb</tt>'s load path.
      # [environment] The environment every command starts from, with the
      #               developer's toolchain variables removed.
      # [run] What runs a command (Runner).
      def initialize(ruby:, work:, load_path:, environment:, run:)
        @ruby = ruby
        @work = work
        @load_path = load_path
        @environment = environment
        @run = run
      end

      # Compiles the extension the +extconf+ in +folder+ builds for
      # +target+, with the gem's build options +args+, its Init function
      # renamed <tt>Init_fledge_NUMBER</tt>, or, when its gem depends on
      # rb_sys (+rust+), with Cargo, and returns its Report. With +shared+
      # it makes the shared object mkmf makes on a desktop instead, its
      # Init function its own, and returns its Library, whose links the
      # caller knows.
      def call(target, gem, folder, extconf, args, number, rust:, shared: false)
        init = "Init_fledge_#{number}"
        report = File.join(folder, "fledge-report.json")
        env = @environment.merge(target.environment).merge("FLEDGE_INIT" => init, "FLEDGE_REPORT" => report, **RUST_FILES)
        env["FLEDGE_SHARED"] = "1" if shared
        what = "compiling #{gem}'s extension #{extconf} for #{target.name}"
        includes = [MobileExtensions.rbconfig_folder(target, @work), *@load_path].flat_map { |path| ["-I", path] }
        shims = rust ? [write("fledge_mobile_mkmf.rb", SHIM), write("fledge_mobile_rb_sys.rb", Rust::SHIM)] : [write("fledge_mobile_mkmf.rb", SHIM)]
        @run.call(env, @ruby, "--disable-gems", *includes, *shims.flat_map { |shim| ["-r", shim] }, extconf, *args, chdir: folder, what:)
        reports = JSON.parse(File.read(report))
        make(env, reports, folder, gem, target, what:, shared:)
        describe(reports, folder, init, gem, target, env, shared:)
      end

      # The FfiLibrary of the library for Ruby's ffi that the Makefile an
      # <tt>extconf.rb</tt> wrote in +folder+ for an Apple +target+ links,
      # once #call has made its archive and found no Init function in it,
      # as sassc's <tt>extconf.rb</tt> builds libsass. It runs mkmf's own
      # rule, the one a desktop's <tt>make</tt> runs, which links the
      # objects <tt>make static</tt> compiled, with the target's compilers
      # through RakeBuild::DYLIB, which links a dynamic library where
      # mkmf's +LDSHARED+ asks for a bundle, as for a Rakefile's library.
      # mkmf links no libruby into it, since the phone's Ruby has no shared
      # one. Its file is the feature's; its path in the gem and its links
      # the caller knows.
      def ffi_library(target, gem, folder)
        report = JSON.parse(File.read(File.join(folder, "fledge-report.json"))).fetch(0)
        dylib = write("fledge_dylib.sh", RakeBuild::DYLIB)
        tools = %w[CC CXX].map { |name| "#{name}=/bin/sh #{dylib} #{target.environment.fetch("FLEDGE_#{name}")}" }
        @run.call(@environment.merge(target.environment), "make", *tools, "all", chdir: folder,
          what: "linking #{gem}'s library for ffi #{report.fetch('library')} for #{target.name}")
        library = File.join(folder, report.fetch("library"))
        raise Error, "#{gem}'s extconf.rb made no #{File.basename(library)} for #{target.name}" unless File.file?(library)

        FfiLibrary.new(gem: gem.name, file: "#{report.fetch('feature')}#{File.extname(library)}", path: library, links: [])
      end

      # Runs the Makefile the extconf.rb in +folder+ wrote: <tt>make
      # static</tt> for mkmf's, which makes the static archive, or with
      # +shared+ its default goal, the shared object; or for
      # rb-sys's, the goal that has Cargo make the static library, with the
      # Makefile's own Cargo arguments, which the shim made from the
      # developer's RB_SYS_EXTRA_CARGO_ARGS where it is set.
      private def make(env, reports, folder, gem, target, what:, shared:)
        return @run.call(env, "make", *(shared ? [] : ["static"]), chdir: folder, what:) unless reports.any? { |report| report["rust"] }

        triple = target.environment.fetch("CARGO_BUILD_TARGET")
        Rust.check(triple, gem: gem.to_s, env:)
        @run.call(env.merge("RB_SYS_EXTRA_CARGO_ARGS" => nil), "make", "-f", Rust::MAKEFILE, "SOEXT=a", "fledge-rust", chdir: folder, what:)
      end

      # What one extension's build came to, from the shim's +reports+ and
      # the Makefile in +folder+, which make reads with +env+.
      private def describe(reports, folder, init, gem, target, env, shared:)
        raise Error, "#{gem}'s extconf.rb called create_makefile #{reports.size} times, and Fledge links one extension for each" if reports.size != 1

        report = reports.first
        return describe_rust(report, folder, gem, target) if report["rust"]

        archive = File.join(folder, report.fetch("archive"))
        raise Error, "#{gem}'s extension made no #{File.basename(archive)} for #{target.name}" unless File.file?(archive)

        libs = "#{report.fetch('libs')} #{Linking.local_libs(env, folder)}"
        if shared
          return Library.new(gem: gem.name, feature: report.fetch("feature"), path: archive, flags: Linking.link_flags(libs, dir: folder), links: [])
        end

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

      # Writes +text+ to the file +name+ in the build's folder, and
      # returns its path.
      private def write(name, text)
        path = File.join(@work, name)
        File.write(path, text)
        path
      end
    end
  end
end
