# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# SPDX-FileComment: Adapted from tasks/license_audit/source_bundle.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../../lib/fledge/archive"
require_relative "../../lib/fledge/download"
require_relative "../download_cache"

class LicenseAudit
  # The complete corresponding source of a platform's LGPL libraries, of
  # the program an LGPL library is linked into (the AppImage runtime, ADR
  # 010), and of a component whose license asks that its source be
  # available (NSIS), in the runtime's own notices/sources/, which every
  # app copies, and as one .tar.gz that each release publishes beside
  # that platform's runtime. The runtime's NOTICES names both.
  #
  # For each component of runtime/licenses.yml that has a source pin and
  # ships on the platform, a folder holds the pinned source exactly as
  # downloaded (checked against its SHA-256), the license texts, and a
  # BUILD.txt that says how the runtime's copy was built from it and how
  # to replace that copy. The LGPL asks for the library's source, not the
  # app's: nothing of the app or of Fledge's launcher goes in. The source
  # travels with the app, so that whoever conveys the app conveys the
  # source with it (LGPL-2.1, section 6(a)) whatever becomes of the
  # release's host (ADR 004, section 5).
  class SourceBundle
    # Where in a runtime, and so in an app, the sources are.
    FOLDER = "notices/sources"

    def initialize(platform:, version:, map: MAP, sources: SOURCES, downloads: File.join(ROOT, "tmp", "downloads"))
      @platform = platform
      @version = version
      @map = YAML.safe_load_file(map)
      @sources = YAML.safe_load_file(sources)
      @downloads = downloads
    end

    # The components that ship on the platform with a source pin.
    def components
      @map.fetch("components").select do |entry|
        entry["source"] && entry.fetch("kind") != "source" && entry.fetch("platforms").include?(@platform)
      end
    end

    # Writes each component's folder into the runtime folder +runtime+,
    # under FOLDER, and returns FOLDER's path there, or nil when the
    # platform ships nothing whose source Fledge publishes.
    def copy_into(runtime)
      return nil if components.empty?

      folder = File.join(runtime, FOLDER)
      FileUtils.mkdir_p(folder)
      components.each { |entry| add_component(folder, entry) }
      folder
    end

    # Writes the bundle into +directory+ and returns its path, or nil
    # when the platform ships nothing whose source Fledge publishes.
    def write(directory)
      return nil if components.empty?

      name = Notices.source_bundle(@version, @platform)
      top = File.basename(name, ".tar.gz")
      path = File.join(directory, name)
      FileUtils.mkdir_p(directory)
      Dir.mktmpdir("source-bundle") do |stage|
        folder = File.join(stage, top)
        FileUtils.mkdir_p(folder)
        File.write(File.join(folder, "README.txt"), readme)
        components.each { |entry| add_component(folder, entry) }
        Fledge::Archive.pack(folder, to: path)
      end
      path
    end

    private def add_component(top, entry)
      folder = File.join(top, entry.fetch("id"))
      pin = @sources.fetch(entry.fetch("source"))
      source = pin.fetch("source", pin)
      FileUtils.mkdir_p(folder)
      FileUtils.cp(fetch(source.fetch("url"), source.fetch("sha256")), folder)
      FileUtils.cp(Dir.glob(File.join(Notices::NOTICES, entry.fetch("notice"), "*")), folder)
      File.write(File.join(folder, "BUILD.txt"), build_text(entry, pin))
    end

    private def fetch(url, sha256)
      DownloadCache.new(@downloads).fetch(url, sha256)
    end

    private def readme
      <<~README
        The complete corresponding source code of what Fledge #{@version}'s
        #{@platform} runtime ships, and so every app or installer built with it,
        under a license that asks for its source: its libraries under the GNU
        Lesser General Public License, any program it ships that such a
        library is linked into, and any component under a license that asks
        that its source be available, such as NSIS's LZMA module, under the
        Common Public License. Each folder holds one component's source exactly
        as its publisher released it, its license, and BUILD.txt, which says
        how the runtime's copy was built and how to replace it. Every app
        built with this runtime carries the same folders in #{FOLDER}/.

        #{components.map { |entry| "  #{entry.fetch('id')}/  #{entry.fetch('name')} #{entry.fetch('version')} (#{entry.fetch('license')})" }.join("\n")}

        Fledge: https://github.com/setdef/Fledge (#{commit})
      README
    end

    private def build_text(entry, pin)
      case entry.fetch("id")
      when "libxcrypt" then libxcrypt_text(pin)
      when "appimage-runtime" then appimage_runtime_text(pin)
      when "libfuse" then libfuse_text(pin)
      when "nsis" then nsis_text(pin)
      when "gmp" then gmp_text(pin)
      else raise "no build instructions for #{entry.fetch('id')}"
      end
    end

    private def libxcrypt_text(pin)
      require_relative "../runtime_builder"
      tarball = File.basename(pin.fetch("url"))
      <<~BUILD
        lib/libcrypt.so.2 in Fledge #{@version}'s #{@platform} runtime is libxcrypt
        #{pin.fetch('version')}, built from #{tarball} (SHA-256 #{pin.fetch('sha256')},
        from #{pin.fetch('url')}) by tasks/runtime_builder.rb
        (RuntimeBuilder::Linux#build_libxcrypt) at Fledge commit #{commit}, on
        Ubuntu 24.04 with its gcc:

          tar -xJf #{tarball}
          cd #{File.basename(tarball, '.tar.xz')}
          ./configure --prefix=PREFIX #{RuntimeBuilder::Linux::LIBXCRYPT_CONFIGURE.join(' ')}
          make
          make install
          strip --strip-unneeded PREFIX/lib/libcrypt.so.2

        To replace it, build libxcrypt (modified or not) the same way and copy
        PREFIX/lib/libcrypt.so.2 over the app's lib/libcrypt.so.2. The app's
        program loads it from there by its RPATH, $ORIGIN/lib, as bin/ruby does
        by $ORIGIN/../lib; both need crypt_r at the symbol version XCRYPT_2.0,
        which every libxcrypt 4 provides.
      BUILD
    end

    private def appimage_runtime_text(pin)
      source = pin.fetch("source")
      binary = pin.fetch("platforms").fetch(@platform)
      archive = File.basename(source.fetch("url"))
      <<~BUILD
        tools/appimage-runtime in Fledge #{@version}'s #{@platform} runtime is AppImage's
        type 2 runtime exactly as AppImage released it, release #{pin.fetch('version')}: the
        file #{File.basename(binary.fetch('url'))} (SHA-256 #{binary.fetch('sha256')},
        from #{binary.fetch('url')}). fledge build puts it, unchanged, at the front
        of every AppImage it writes.

        AppImage built it from the commit #{pin.fetch('commit')} of
        https://github.com/AppImage/type2-runtime, whose source is #{archive}
        in this folder (SHA-256 #{source.fetch('sha256')}, from
        #{source.fetch('url')}). Its scripts/docker/Dockerfile builds it in Alpine
        Linux 3.21 with scripts/common/install-dependencies.sh, which builds libfuse
        #{@sources.fetch('libfuse').fetch('version')} (with patches/libfuse/mount.c.diff, in this folder's
        archive) and squashfuse statically, and scripts/build-runtime.sh, which
        links them, Alpine's zstd, zlib, and mimalloc, and musl into one static
        program, and writes AppImage's magic bytes at offset 8.

        libfuse is under the GNU Lesser General Public License, version 2.1, and
        is linked into this program, so this folder and ../libfuse/ are what its
        section 6(a) asks for: to replace libfuse, build libfuse (modified or not)
        as install-dependencies.sh does, run build-runtime.sh against it, and
        put the program it writes at the front of the app's AppImage in place
        of this one (or into tools/appimage-runtime, before fledge build runs).
      BUILD
    end

    private def libfuse_text(pin)
      <<~BUILD
        libfuse #{pin.fetch('version')}, #{File.basename(pin.fetch('url'))} in this folder (SHA-256
        #{pin.fetch('sha256')}, from #{pin.fetch('url')}), is the
        libfuse that AppImage's type 2 runtime links statically into
        tools/appimage-runtime, with AppImage's patch to its lib/mount.c
        (patches/libfuse/mount.c.diff in ../appimage-runtime/'s archive). Its
        scripts/common/install-dependencies.sh builds it with meson, as a static
        library; ../appimage-runtime/BUILD.txt says how to rebuild the runtime
        with it, or with another libfuse.
      BUILD
    end

    private def nsis_text(pin)
      source = pin.fetch("source")
      binary = pin.fetch("binary")
      <<~BUILD
        tools/nsis/ in Fledge #{@version}'s #{@platform} runtime holds files of NSIS
        #{pin.fetch('version')}'s release for Windows, #{File.basename(binary.fetch('url'))} (SHA-256
        #{binary.fetch('sha256')}, from #{binary.fetch('url')}),
        unchanged: makensis, which fledge build runs to compile an app's setup
        program, and the stub, plug-ins, and Modern UI it compiles one from.
        NSIS built that release from #{File.basename(source.fetch('url'))}, which is in
        this folder (SHA-256 #{source.fetch('sha256')}, from
        #{source.fetch('url')}).

        Every setup program begins with NSIS's stub for solid LZMA compression,
        whose LZMA module is under the Common Public License, version 1.0; its
        section 3 asks that a program distributed in object code say that its
        source is available and how to get it. This folder is that source.
      BUILD
    end

    # What MSYS2 calls each Windows target's environment, its folder, and
    # its compiler's triple.
    GMP_BUILDS = {
      "x64-mingw-ucrt" => { "environment" => "UCRT64", "folder" => "ucrt64", "triple" => "x86_64-w64-mingw32" },
      "aarch64-mingw-ucrt" => { "environment" => "CLANGARM64", "folder" => "clangarm64", "triple" => "aarch64-w64-mingw32" },
    }.freeze

    private def gmp_text(pin)
      build = GMP_BUILDS.fetch(@platform)
      binary = (@platform == "aarch64-mingw-ucrt") ? pin.fetch("arm64") : pin
      package = binary.fetch("package")
      source = File.basename(pin.fetch("url"))
      <<~BUILD
        ruby/bin/ruby_builtin_dlls/libgmp-10.dll in Fledge #{@version}'s #{@platform}
        runtime is GNU MP #{pin.fetch('version')} exactly as RubyInstaller ships it. It is byte
        for byte (SHA-256 #{binary.fetch('dll_sha256')})
        the file #{build.fetch('folder')}/bin/libgmp-10.dll of MSYS2's package
        #{File.basename(package.fetch('url'))} (SHA-256 #{package.fetch('sha256')},
        from #{package.fetch('url')}).

        MSYS2 built that package from #{source} (SHA-256 #{pin.fetch('sha256')},
        from #{pin.fetch('url')}), which is in this folder: GMP's release
        tarball, MSYS2's patches, and the PKGBUILD that builds them, with
        makepkg-mingw in MSYS2's #{build.fetch('environment')} environment. Unpack it with
        tar --zstd -xf #{source}.

        To replace it, build GMP (modified or not) as a DLL for #{build.fetch('triple')}
        that uses the UCRT, name it libgmp-10.dll, and copy it over the app's
        ruby\\bin\\ruby_builtin_dlls\\libgmp-10.dll. Ruby's DLL finds it there
        through the side-by-side assembly ruby_builtin_dlls, whose manifest names
        the file but no hash, and imports GMP's mpz functions by name.
      BUILD
    end

    private def commit
      out, status = Open3.capture2("git", "-C", ROOT, "rev-parse", "HEAD")
      status.success? ? out.strip : "unknown"
    rescue SystemCallError
      "unknown"
    end
  end
end
