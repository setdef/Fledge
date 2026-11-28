# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require_relative "unix"

class RuntimeBuilder
  # musl Linux (Alpine and the CI images built on it): CRuby built from
  # its pinned source on the computer it is for, as python-build-standalone
  # builds Python, because rv-ruby's musl
  # builds link the standard library's extensions into their own
  # bin/ruby, where a launcher linked against their libruby cannot reach
  # them. It is configured as rv-ruby's
  # glibc builds are, a static libruby that finds its library from the
  # program that holds it, with YJIT, but with each extension a shared
  # object, as on glibc, and OpenSSL, libyaml, libffi, and zlib built
  # from their pinned sources and linked statically into the extensions
  # that use them. musl itself is the computer's: every musl Linux has
  # it, as every glibc Linux has glibc, and its own crypt(3) serves
  # String#crypt, so no libxcrypt ships.
  class Musl < Unix
    # The only libraries the launcher and bin/ruby may need: musl's C
    # library, which is also its dynamic linker.
    ALLOWED = /\A(?:libc\.musl-(?:x86_64|aarch64)\.so\.1|ld-musl-(?:x86_64|aarch64)\.so\.1)\z/

    # The edits of Ruby's source a musl runtime takes (RubySource):
    # thread_c, since musl's pthread_setname_np, as bionic's, reads the
    # pthread_t of a thread that has ended, which join freed, and
    # Thread#name= on such a thread crashed Ruby (ruby/spec's
    # core/thread/to_s_spec.rb, line 18, a segmentation fault in stock
    # Ruby and the app alike in run 43354884978, on both musl runtimes).
    EDITS = %i[thread_c].freeze

    # The architecture of each musl target, as OpenSSL's Configure names
    # its Linux targets.
    ARCHES = { "x86_64-linux-musl" => "x86_64", "aarch64-linux-musl" => "aarch64" }.freeze

    def compile(output, sources, _rpath)
      cc = ENV.fetch("CC", "cc")
      analyze_with_gcc(cc, sources)
      static = File.join(@prefix, "lib", "libruby-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      objects = compile_objects(cc, output, sources, *Hardening::COMPILE.fetch(:musl))
      @builder.run(cc, *objects, *Hardening::LINK.fetch(:musl), "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", *libruby_libraries, "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      check_dynamic_section(output)
    end

    def finish(stage)
      Pruning.strip_extensions(@builder, File.join(stage, "lib", "ruby"))
      copy_appimage_runtime(File.join(stage, "tools", "appimage-runtime"))
    end

    # Builds Ruby, and the libraries its extensions link statically, from
    # their musl-ruby pins (RubyBuild), and returns the prefix, which the
    # Unix recipe copies a runtime from as it copies rv-ruby's.
    private def unpack_ruby
      RubyBuild.new(builder: @builder, build_dir: @build_dir, pins: @builder.sources.fetch("musl-ruby"), edits: EDITS,
        openssl_target: "linux-#{ARCHES.fetch(@builder.platform.name)}").call
    end

    # The prefix RubyBuild built OpenSSL and libyaml into, whose headers,
    # static libraries, and pkg-config files gems compile against, as
    # jdx/ruby's tree holds them on glibc Linux (Unix::GEM_LIBRARIES).
    private def gem_libraries
      File.join(@build_dir, "deps")
    end

    # The libraries libruby-static.a needs, as its own Ruby links them
    # (RbConfig's LIBS), which on musl are all in its C library.
    private def libruby_libraries
      %w[-lm -lpthread]
    end

    private def copy_appimage_runtime(to)
      pin = @builder.sources.fetch("appimage-runtime").fetch("platforms").fetch(@builder.platform.name)
      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(@builder.fetch(pin.fetch("url"), pin.fetch("sha256")), to)
      FileUtils.chmod(0o755, to)
    end

    def hardening_kind
      :musl
    end

    private def os_file
      "linux.c"
    end

    private def check_dynamic_section(output)
      dynamic = @builder.capture("readelf", "-d", output)
      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "#{output} needs libraries a musl Linux does not have: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
