# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "etc"
require "fileutils"

class RuntimeBuilder
  # The program at the front of every AppImage (ADR 009): AppImage's type
  # 2 runtime, built as its own scripts build it (clang, -Os, its linker
  # script for the sections AppImage's tools read, its magic bytes at
  # offset 8), but against glibc instead of musl, with squashfuse and zlib
  # linked statically, and with no libfuse: Fledge's fuse.c loads the
  # computer's own libfuse3.so.3 when it mounts, and runtime.patch makes
  # the runtime extract and run the AppImage where it cannot mount, so
  # nothing LGPL is linked into it (decision 8). It needs libfuse's
  # headers, which declare what fuse.c loads, and nothing else of
  # libfuse; CI installs Ubuntu's libfuse3-dev for them.
  class AppImageRuntime
    APPIMAGE = File.join(ROOT, "runtime", "appimage")

    # The magic bytes AppImage's type 2 format puts at offset 8 of the
    # ELF header: "AI" and the type.
    MAGIC = "AI\x02".b

    # What the runtime may link: glibc, which every computer an app runs
    # on has (ADR 001, section 3).
    ALLOWED = /\A(?:libc\.so\.6|ld-linux[-\w.]*\.so\.\d)\z/

    def initialize(builder:, build_dir:)
      @builder = builder
      @work = File.join(build_dir, "appimage-runtime")
    end

    def build(output)
      FileUtils.rm_rf(@work)
      FileUtils.mkdir_p(@work)
      zlib = build_zlib
      squashfuse = build_squashfuse(zlib)
      source = unpack("appimage-runtime")
      @builder.run("patch", "-p1", "-i", File.join(APPIMAGE, "runtime.patch"), chdir: source)
      compile(File.join(source, "src", "runtime"), squashfuse, zlib, output)
    end

    private def pin(name)
      @builder.sources.fetch(name)
    end

    private def unpack(name)
      tarball = @builder.fetch(pin(name).fetch("url"), pin(name).fetch("sha256"))
      folder = File.join(@work, name)
      FileUtils.mkdir_p(folder)
      @builder.run("tar", "-xzf", tarball, "-C", folder, "--strip-components=1")
      folder
    end

    private def build_zlib
      source = unpack("zlib")
      prefix = File.join(@work, "zlib-prefix")
      @builder.run({ "CFLAGS" => "-O2 -fPIC" }, "./configure", "--static", "--prefix=#{prefix}", chdir: source)
      @builder.run("make", "-j#{Etc.nprocessors}", "install", chdir: source)
      prefix
    end

    # squashfuse's libraries, with zlib alone of its decompressors, since
    # Fledge::Squashfs compresses with zlib alone.
    private def build_squashfuse(zlib)
      source = unpack("squashfuse")
      @builder.run({ "CFLAGS" => "-O2 -fPIC" }, "./configure", "--disable-shared", "--enable-static", "--with-zlib=#{zlib}",
        "--without-xz", "--without-lzo", "--without-lz4", "--without-zstd", chdir: source)
      @builder.run("make", "-j#{Etc.nprocessors}", "libsquashfuse.la", "libsquashfuse_ll.la", "libfuseprivate.la", chdir: source)
      FileUtils.mkdir_p(File.join(@work, "include"))
      File.symlink(source, File.join(@work, "include", "squashfuse"))
      source
    end

    private def compile(runtime, squashfuse, zlib, output)
      cc = ENV.fetch("APPIMAGE_CC", "clang")
      commit = pin("appimage-runtime").fetch("commit")[0, 7]
      headers = ["-I#{File.join(@work, 'include')}", "-I#{squashfuse}", "-isystem", "/usr/include/fuse3"]
      flags = ["-std=gnu99", "-Os", "-D_FILE_OFFSET_BITS=64", "-fPIE", *headers]
      fuse = File.join(APPIMAGE, "fuse.c")
      @builder.run(cc, "--analyze", "-Xclang", "-analyzer-werror", *flags, *WARNINGS, fuse, "-o", File.join(@work, "fuse.plist"))
      @builder.run(cc, *flags, *WARNINGS, "-c", fuse, "-o", File.join(@work, "fuse.o"))
      @builder.run(cc, *flags, "-Wall", "-Werror", "-DGIT_COMMIT=\"#{commit}+fledge\"", "-c", "runtime.c", "-o", File.join(@work, "runtime.o"),
        chdir: runtime)
      libraries = %w[libsquashfuse_ll.a libfuseprivate.a libsquashfuse.a].map { |name| File.join(squashfuse, ".libs", name) }
      FileUtils.mkdir_p(File.dirname(output))
      @builder.run(cc, "-pie", "-T", "data_sections.ld", "-Wl,--gc-sections", "-static-libgcc", File.join(@work, "runtime.o"),
        File.join(@work, "fuse.o"), *libraries, File.join(zlib, "lib", "libz.a"), "-o", output, chdir: runtime)
      @builder.run("strip", "--strip-all", output)
      File.open(output, "r+b") do |file|
        file.seek(8)
        file.write(MAGIC)
      end
      check(output)
    end

    private def check(output)
      raise "#{output} lacks AppImage's magic bytes" unless File.binread(output, 3, 8) == MAGIC

      dynamic = @builder.capture("readelf", "-d", output)
      needed = dynamic.scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
      foreign = needed.grep_v(ALLOWED)
      raise "#{output} links libraries a computer may lack: #{foreign.join(', ')}" unless foreign.empty?
    end
  end
end
