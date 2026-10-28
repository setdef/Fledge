# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/source_bundle.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require "fileutils"
require "open3"
require_relative "../../lib/fledge/download"
require_relative "../../lib/fledge/entry"
require_relative "../../lib/fledge/tar_gz"
require_relative "../download_cache"

class LicenseAudit
  # The complete corresponding source of a platform's LGPL libraries, as
  # one .tar.gz that each release publishes beside that platform's
  # runtime, and that the runtime's NOTICES names.
  #
  # For each component of runtime/licenses.yml that has a source pin and
  # ships on the platform, the bundle holds the pinned source exactly as
  # downloaded (checked against its SHA-256), the license texts, and a
  # BUILD.txt that says how the runtime's copy was built from it and how
  # to replace that copy. The LGPL asks for the library's source, not the
  # app's: nothing of the app or of Fledge's launcher goes in.
  class SourceBundle
    def initialize(platform:, version:, map: MAP, sources: SOURCES, downloads: File.join(ROOT, "tmp", "downloads"))
      @platform = platform
      @version = version
      @map = YAML.safe_load_file(map)
      @sources = YAML.safe_load_file(sources)
      @downloads = downloads
    end

    # The LGPL components that ship on the platform.
    def components
      @map.fetch("components").select { |entry| entry["source"] && entry.fetch("platforms").include?(@platform) }
    end

    # Writes the bundle into +directory+ and returns its path, or nil
    # when the platform ships no LGPL library.
    def write(directory)
      return nil if components.empty?

      name = Notices.source_bundle(@version, @platform)
      top = File.basename(name, ".tar.gz")
      path = File.join(directory, name)
      FileUtils.mkdir_p(directory)
      mtime = Integer(ENV.fetch("SOURCE_DATE_EPOCH", Time.now.to_i.to_s))
      Fledge::TarGz.write(path, mtime:) do |tar|
        tar.add(Fledge::Entry.directory(top))
        tar.add(Fledge::Entry.file("#{top}/README.txt", readme))
        components.each { |entry| add_component(tar, top, entry) }
      end
      path
    end

    private def add_component(tar, top, entry)
      folder = "#{top}/#{entry.fetch('id')}"
      pin = @sources.fetch(entry.fetch("source"))
      tar.add(Fledge::Entry.directory(folder))
      source = fetch(pin.fetch("url"), pin.fetch("sha256"))
      tar.add(Fledge::Entry.file("#{folder}/#{File.basename(source)}", File.binread(source)))
      Dir.glob(File.join(Notices::NOTICES, entry.fetch("notice"), "*")).each do |notice|
        tar.add(Fledge::Entry.file("#{folder}/#{File.basename(notice)}", File.binread(notice)))
      end
      tar.add(Fledge::Entry.file("#{folder}/BUILD.txt", build_text(entry, pin)))
    end

    private def fetch(url, sha256)
      DownloadCache.new(@downloads).fetch(url, sha256)
    end

    private def readme
      <<~README
        The complete corresponding source code of the libraries under the GNU
        Lesser General Public License that Fledge #{@version}'s #{@platform} runtime
        ships, and so every app built with it. Each folder holds one library's
        source exactly as its publisher released it, its license, and BUILD.txt,
        which says how the runtime's copy was built and how to replace it.

        #{components.map { |entry| "  #{entry.fetch('id')}/  #{entry.fetch('name')} #{entry.fetch('version')} (#{entry.fetch('license')})" }.join("\n")}

        Fledge: https://github.com/setdef/Fledge (#{commit})
      README
    end

    private def build_text(entry, pin)
      case entry.fetch("id")
      when "libxcrypt" then libxcrypt_text(pin)
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

    private def gmp_text(pin)
      package = pin.fetch("package")
      source = File.basename(pin.fetch("url"))
      <<~BUILD
        ruby/bin/ruby_builtin_dlls/libgmp-10.dll in Fledge #{@version}'s #{@platform}
        runtime is GNU MP #{pin.fetch('version')} exactly as RubyInstaller ships it. It is byte
        for byte (SHA-256 #{pin.fetch('dll_sha256')})
        the file ucrt64/bin/libgmp-10.dll of MSYS2's package
        #{File.basename(package.fetch('url'))} (SHA-256 #{package.fetch('sha256')},
        from #{package.fetch('url')}).

        MSYS2 built that package from #{source} (SHA-256 #{pin.fetch('sha256')},
        from #{pin.fetch('url')}), which is in this folder: GMP's release
        tarball, MSYS2's patches, and the PKGBUILD that builds them, with
        makepkg-mingw in MSYS2's UCRT64 environment. Unpack it with
        tar --zstd -xf #{source}.

        To replace it, build GMP (modified or not) as a DLL for x86_64-w64-mingw32
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
