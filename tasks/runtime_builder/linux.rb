# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require "fileutils"
require_relative "app_image_runtime"
require_relative "unix"

class RuntimeBuilder
  # Linux: link libruby whole and export its symbols (-rdynamic), take
  # libgcc's unwinder statically, and link libxcrypt dynamically from
  # the runtime's lib/ (see runtime/launcher/unix.c).
  class Linux < Unix
    # libxcrypt's configure options: those of rv-ruby's
    # rv-portable-libxcrypt formula, shared instead of static. The LGPL
    # source bundle (tasks/license_audit/source_bundle.rb) prints them
    # as the way the runtime's copy was built.
    LIBXCRYPT_CONFIGURE = %w[
      --enable-shared
      --disable-static
      --disable-obsolete-api
      --disable-xcrypt-compat-files
      --disable-failure-tokens
      --disable-valgrind
    ].freeze

    # The shared libraries the launcher may need: glibc's, and the
    # runtime's own libxcrypt.
    ALLOWED = /\A(?:libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux[-\w.]*\.so\.\d|libcrypt\.so\.\d+)\z/

    # Compiles +sources+ with libruby into the program +output+, which
    # finds the runtime's libcrypt through the RPATH +rpath+: $ORIGIN/lib
    # for the launcher at the runtime's top, $ORIGIN/../lib for bin/ruby.
    def compile(output, sources, rpath)
      xcrypt = (@xcrypt ||= build_libxcrypt)
      cc = ENV.fetch("CC", "cc")
      sources.each do |source|
        @builder.run(cc, "-fanalyzer", "-Werror", "-std=gnu11", *includes, "-c", source, "-o", File::NULL)
      end
      static = File.join(@prefix, "lib", "libruby-static.a")
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-std=gnu11", "-O2", *WARNINGS, *includes, *sources, "-rdynamic", "-static-libgcc",
        "-Wl,--whole-archive", static, "-Wl,--no-whole-archive", "-L#{File.join(xcrypt, 'lib')}", "-lcrypt",
        "-Wl,--disable-new-dtags,-rpath,#{rpath}", "-lrt", "-ldl", "-lm", "-lpthread", "-o", output)
      @builder.run("strip", "--strip-unneeded", output)
      copy_libcrypt(xcrypt, File.join(@builder.stage, "lib"))
      check_dynamic_section(output, rpath)
    end

    # Strips debug sections from extensions, and removes the RUNPATHs
    # rv-ruby's build machine left in some (zlib.so names a Linuxbrew
    # folder), so no extension looks for libraries outside the runtime.
    # Then builds the AppImage runtime into tools/.
    def finish(stage)
      Dir.glob(File.join(stage, "lib", "ruby", "**", "*.so")).each do |extension|
        @builder.run("strip", "--strip-debug", extension)
        @builder.run("patchelf", "--remove-rpath", extension) unless @builder.capture("patchelf", "--print-rpath", extension).strip.empty?
      end
      AppImageRuntime.new(builder: @builder, build_dir: @build_dir).build(File.join(stage, "tools", "appimage-runtime"))
    end

    private def build_libxcrypt
      pin = @builder.sources.fetch("libxcrypt")
      tarball = @builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      source = File.join(@build_dir, "libxcrypt")
      prefix = File.join(@build_dir, "libxcrypt-prefix")
      FileUtils.mkdir_p(source)
      @builder.run("tar", "-xJf", tarball, "-C", source, "--strip-components=1")
      @builder.run("./configure", "--prefix=#{prefix}", *LIBXCRYPT_CONFIGURE, chdir: source)
      @builder.run("make", "-j#{Etc.nprocessors}", chdir: source)
      @builder.run("make", "install", chdir: source)
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
