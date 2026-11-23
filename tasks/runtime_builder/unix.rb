# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "recipe"

class RuntimeBuilder
  # macOS and Linux: a prebuilt relocatable Ruby (rv-ruby's on macOS,
  # jdx/ruby's on glibc Linux, Fledge's own on musl), whose static
  # libruby the launcher links, so each builds only on its own platform. The runtime is the
  # launcher with bin/, lib/ruby, the static libruby, and
  # libexec/cert.pem beside it.
  class Unix < Recipe
    def build(stage)
      @prefix = unpack_ruby
      copy_ruby(stage)
      compile(File.join(stage, "launcher"), launcher_sources, "$ORIGIN/lib")
      compile(File.join(stage, "bin", "ruby"), ruby_sources, "$ORIGIN/../lib")
      finish(stage)
    end

    # The launcher and bin/ruby, which Hardening reads.
    def programs(stage)
      [File.join(stage, "launcher"), File.join(stage, "bin", "ruby")]
    end

    # Ruby's own main.c, which chooses its locale as the launcher does,
    # and hands an app's own program back to its launcher.
    private def ruby_sources
      %w[ruby_main.c relaunch.c config.c locale.c].map { |file| File.join(LAUNCHER, file) } << File.join(LAUNCHER, os_file)
    end

    private def launcher_sources
      (%w[unix.c scrub.c config.c bundler.c locale.c] + launcher_os_files).map { |file| File.join(LAUNCHER, file) } <<
        File.join(LAUNCHER, os_file)
    end

    # The files only this system's launcher has, and not its bin/ruby.
    private def launcher_os_files
      []
    end

    # Runs gcc's static analyzer over each of +sources+, warnings as
    # errors, as clang's checks every other platform's launcher.
    private def analyze_with_gcc(cc, sources)
      sources.each do |source|
        @builder.run(cc, "-fanalyzer", "-Werror", "-std=gnu11", *includes, "-c", source, "-o", File::NULL)
      end
    end

    private def includes
      headers = Dir.glob(File.join(@prefix, "include", "ruby-*")).first or raise "#{@prefix} has no Ruby headers"
      arch = Dir.glob(File.join(headers, "*")).find { |dir| File.directory?(dir) && File.basename(dir) != "ruby" }
      ["-isystem", arch.to_s, "-isystem", headers, "-I", LAUNCHER]
    end

    private def unpack_ruby
      pin = @builder.sources.fetch("ruby").fetch("platforms").fetch(@builder.platform.name)
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      unpacked = File.join(@build_dir, "rv-ruby")
      FileUtils.mkdir_p(unpacked)
      @builder.run("tar", "-xzf", tarball, "-C", unpacked, "--no-same-owner")
      Unix.prefix(unpacked, @builder.sources.fetch("ruby").fetch("version"))
    end

    # The one Ruby prefix in the archive unpacked into +unpacked+: NAME/VERSION/
    # in rv-ruby's archives and Fledge's own (ruby/VERSION/), ruby-VERSION/
    # in jdx/ruby's.
    def self.prefix(unpacked, version)
      prefixes = [*Dir.glob(File.join(unpacked, "*", version)), *Dir.glob(File.join(unpacked, "ruby-#{version}"))]
      prefixes = prefixes.select { |prefix| File.directory?(File.join(prefix, "bin")) }
      raise "#{unpacked} does not hold one Ruby #{version} prefix: #{prefixes}" unless prefixes.size == 1

      prefixes.first.to_s
    end

    # Copies rv-ruby's bin/ (whose ruby compile then replaces with one
    # built from the same libruby as the launcher; the rest are the gems'
    # executables), lib/ruby, Ruby's headers (include/, which require
    # "mkmf" looks for; Pruning.prune), the static libruby
    # (#copy_static_libruby), and the CA bundle.
    private def copy_ruby(stage)
      FileUtils.mkdir_p(File.join(stage, "lib"))
      FileUtils.cp_r(File.join(@prefix, "bin"), File.join(stage, "bin"))
      FileUtils.rm_f(File.join(stage, "bin", "ruby"))
      FileUtils.cp_r(File.join(@prefix, "lib", "ruby"), File.join(stage, "lib", "ruby"))
      # Ruby's own headers, which mkmf reads, and those of the libraries
      # gems compile against (#gem_libraries); not the rest jdx/ruby's
      # tree adds beside them (zlib's, and libxcrypt's crypt.h).
      FileUtils.mkdir_p(File.join(stage, "include"))
      Dir.glob(File.join(@prefix, "include", "ruby-*")).each { |headers| FileUtils.cp_r(headers, File.join(stage, "include")) }
      Unix.copy_gem_libraries(gem_libraries, stage)
      FileUtils.chmod_R("u+w", [File.join(stage, "lib"), File.join(stage, "bin"), File.join(stage, "include")])
      removed = Pruning.prune(File.join(stage, "lib", "ruby"), @builder.bundled_gems)
      Pruning.prune_bin(File.join(stage, "bin"), removed)
      @builder.install_rubygems_defaults(File.join(stage, "lib", "ruby"))
      FileUtils.mkdir_p(File.join(stage, "libexec"))
      FileUtils.cp(File.join(@prefix, "libexec", "cert.pem"), File.join(stage, "libexec", "cert.pem"))
      copy_static_libruby(stage)
    end

    # What a gem fledge build compiles finds of OpenSSL and libyaml, the
    # libraries the runtime's Ruby linked into its openssl and psych
    # extensions, which no computer an app goes to can be counted on to
    # have: their headers, static libraries, and pkg-config files, as
    # jdx/ruby keeps them in its tree for compiling gems
    # (libexec/package.rb, copy_native_gem_dependencies, at 09c4b6b).
    # No app holds them (Fledge::Assembly::RuntimeFolder).
    GEM_LIBRARIES = %w[
      include/openssl
      include/yaml.h
      lib/libssl.a
      lib/libcrypto.a
      lib/libyaml.a
      lib/pkgconfig/openssl.pc
      lib/pkgconfig/libssl.pc
      lib/pkgconfig/libcrypto.pc
      lib/pkgconfig/yaml-0.1.pc
    ].freeze

    # The prefix that holds GEM_LIBRARIES: the Ruby's own, as jdx/ruby's
    # tree holds them.
    private def gem_libraries
      @prefix
    end

    # Copies GEM_LIBRARIES from the prefix +from+ into +stage+, each that
    # +from+ holds, with each pkg-config file naming the folder it is in
    # (<tt>${pcfiledir}/../..</tt>) wherever it named +from+, so that it
    # holds wherever the runtime is unpacked.
    def self.copy_gem_libraries(from, stage)
      GEM_LIBRARIES.each do |path|
        source = File.join(from, path)
        next unless File.exist?(source)

        target = File.join(stage, path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(source, target)
        FileUtils.chmod_R("u+w", target)
        File.write(target, File.read(target).gsub(from, "${pcfiledir}/../..")) if path.end_with?(".pc")
      end
    end

    # Copies the static libruby into the runtime's lib/, stripped of its
    # debug information. mkmf links the test program of every have_func,
    # have_library, and try_link against $(LIBRUBYARG), which for a static
    # Ruby is LIBRUBYARG_STATIC, -lruby.4.1-static from $(libdir)
    # (mkmf.rb, link_config, lines 541 to 553, at Ruby 4.1.0-preview1), so
    # without it an app's own running mkmf raises "The compiler failed to
    # generate an executable file". No other static library comes along:
    # rv-ruby's lib/libcrypt.a is libxcrypt, which is LGPL, and the linker
    # finds the system's -lcrypt instead.
    #
    # A link reads the archive's code, data, symbols, and relocations,
    # never its debug information, and the launcher and bin/ruby link the
    # prefix's own copy and are stripped themselves, so strip -S, which
    # GNU's strip and Apple's both take for "debug information only",
    # leaves out what nothing reads: most of the file on Linux, where
    # Ruby's C is compiled with DWARF (90 MB to 19 MB for rv-ruby's x86_64
    # build, 165 MB to 20 MB for Fledge's musl one, at Ruby
    # 4.1.0-preview1), and on macOS the debug map of the Rust in YJIT and
    # ZJIT, which names object files only rv-ruby's build machine had
    # (13.3 MB to 11.5 MB).
    private def copy_static_libruby(stage)
      Dir.glob(File.join(@prefix, "lib", "libruby*-static.a")).each do |library|
        copy = File.join(stage, "lib", File.basename(library))
        FileUtils.cp(library, copy)
        FileUtils.chmod("u+w", copy)
        @builder.run("strip", "-S", copy)
      end
    end
  end
end
