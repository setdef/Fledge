# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "etc"
require "fileutils"
require_relative "../../lib/fledge/binary"
require_relative "unix"

class RuntimeBuilder
  # Linux: link libruby whole and export its symbols (-rdynamic), take
  # libgcc's unwinder statically, and link libxcrypt dynamically from
  # the runtime's lib/ (see runtime/launcher/unix.c).
  class Linux < Unix
    # libxcrypt's configure options: those of rv-ruby's
    # rv-portable-libxcrypt formula, shared instead of static, and with
    # libxcrypt's own --disable-werror, which drops only the -Werror its
    # configure adds and keeps every warning it enables. libxcrypt 4.5.2
    # does not build otherwise where GCC defaults to C23 (GCC 15) and
    # glibc's strchr keeps its argument's const (glibc 2.43): its
    # crypt-sm3-yescrypt.c and crypt-gost-yescrypt.c assign that result
    # to a char *, which libxcrypt fixed after 4.5.2, in commit
    # 174c24d6e8. The LGPL source bundle
    # (tasks/license_audit/source_bundle.rb) prints these options as the
    # way the runtime's copy was built.
    LIBXCRYPT_CONFIGURE = %w[
      --enable-shared
      --disable-static
      --disable-obsolete-api
      --disable-xcrypt-compat-files
      --disable-failure-tokens
      --disable-valgrind
      --disable-werror
    ].freeze

    # The shared libraries the launcher may need: glibc's, and the
    # runtime's own libxcrypt.
    ALLOWED = /\A(?:libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux[-\w.]*\.so\.\d|libcrypt\.so\.\d+)\z/

    # Compiles +sources+ with libruby into the program +output+, which
    # finds the runtime's libcrypt through the RPATH +rpath+: $ORIGIN/lib
    # for the launcher at the runtime's top, $ORIGIN/../lib for bin/ruby.
    def compile(output, sources, rpath)
      xcrypt = (@xcrypt ||= Linux.build_libxcrypt(@builder, @build_dir))
      cc = ENV.fetch("CC", "cc")
      analyze_with_gcc(cc, sources)
      static = File.join(@prefix, "lib", "libruby-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, *Hardening::COMPILE.fetch(:glibc), *includes, *sources, *Hardening::LINK.fetch(:glibc), "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", "-L#{File.join(xcrypt, 'lib')}", "-lcrypt",
        "-Wl,--disable-new-dtags,-rpath,#{rpath}", "-lrt", "-ldl", "-lm", "-lpthread", "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      copy_libcrypt(xcrypt, File.join(@builder.stage, "lib"))
      check_dynamic_section(output, rpath)
    end

    # Strips debug sections from extensions, and removes the RUNPATHs
    # the pinned Ruby's build machine left in some (rv-ruby's zlib.so
    # named a Linuxbrew folder), so no extension looks for libraries
    # outside the runtime.
    # Then puts AppImage's released runtime into tools/.
    def finish(stage)
      Dir.glob(File.join(stage, "lib", "ruby", "**", "*.so")).each do |extension|
        @builder.run("strip", "--strip-debug", extension)
        @builder.run("patchelf", "--remove-rpath", extension) unless @builder.capture("patchelf", "--print-rpath", extension).strip.empty?
      end
      copy_appimage_runtime(File.join(stage, "tools", "appimage-runtime"))
      floor = @builder.platform.glibc_minimum.to_s
      late = Linux.above_glibc_floor(stage, floor, readers: Fledge::Binary::Readers.local("linux"))
      raise "these need a glibc newer than #{floor}, the floor of #{@builder.platform} apps: #{late.join(', ')}" unless late.empty?
    end

    # Each ELF file in +stage+ that needs a newer glibc than +floor+, as
    # "PATH (VERSION)", PATH relative to +stage+: the newest GLIBC_
    # symbol version it references, as Fledge::NativeBuild::Floors reads
    # a compiled gem's.
    def self.above_glibc_floor(stage, floor, readers:)
      files = Dir.glob("**/*", base: stage).sort.map { |path| File.join(stage, path) }
      Fledge::Binary.read(files, readers:).filter_map do |path, binary|
        found = binary.glibc_minimum
        "#{path.delete_prefix("#{stage}/")} (#{found})" if found && Gem::Version.new(found) > Gem::Version.new(floor)
      end
    end

    # AppImage's type 2 runtime, the program at the front of every
    # AppImage, as AppImage releases it for this
    # platform's architecture, pinned by SHA-256: built statically
    # against musl, with libfuse (LGPL-2.1), squashfuse, zstd, zlib, and
    # mimalloc linked in, whose sources the release's source bundle holds.
    private def copy_appimage_runtime(to)
      pin = @builder.sources.fetch("appimage-runtime").fetch("platforms").fetch(@builder.platform.name)
      FileUtils.mkdir_p(File.dirname(to))
      FileUtils.cp(@builder.fetch(pin.fetch("url"), pin.fetch("sha256")), to)
      FileUtils.chmod(0o755, to)
    end

    # Builds libxcrypt from its pin, shared, with LIBXCRYPT_CONFIGURE,
    # into a prefix in +build_dir+, and returns the prefix. RubyArchive
    # builds the same library for the Ruby it publishes.
    def self.build_libxcrypt(builder, build_dir)
      pin = builder.sources.fetch("libxcrypt")
      tarball = builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      source = File.join(build_dir, "libxcrypt")
      prefix = File.join(build_dir, "libxcrypt-prefix")
      FileUtils.mkdir_p(source)
      # The build owns what it unpacks, whoever owned it in the archive:
      # as root in a container, tar otherwise keeps the archive's owners,
      # which a user namespace cannot map.
      builder.run("tar", "-xJf", tarball, "-C", source, "--strip-components=1", "--no-same-owner")
      builder.run("./configure", "--prefix=#{prefix}", *LIBXCRYPT_CONFIGURE, chdir: source)
      builder.run("make", "-j#{Etc.nprocessors}", chdir: source)
      builder.run("make", "install", chdir: source)
      prefix
    end

    private def copy_libcrypt(xcrypt, lib)
      linked = Dir.glob(File.join(xcrypt, "lib", "libcrypt.so.*")).find { |path| File.basename(path).match?(/\Alibcrypt\.so\.\d+\z/) }
      raise "libxcrypt built no libcrypt.so.N" unless linked

      FileUtils.mkdir_p(lib)
      target = File.join(lib, File.basename(linked))
      FileUtils.cp(File.realpath(linked), target)
      FileUtils.chmod(0o755, target)
      @builder.run("strip", "--strip-unneeded", target)
    end

    def hardening_kind
      :glibc
    end

    private def os_file
      "linux.c"
    end

    private def check_dynamic_section(output, rpath)
      dynamic = @builder.capture("readelf", "-d", output)
      raise "#{output} has a RUNPATH, which LD_LIBRARY_PATH overrides" if dynamic.include?("(RUNPATH)")
      raise "#{output} has no RPATH of #{rpath}" unless dynamic.include?("Library rpath: [#{rpath}]")

      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "#{output} needs libraries a runtime does not ship: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
