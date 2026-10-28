# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require_relative "download"
require_relative "entry"
require_relative "error"
require_relative "archive"
require_relative "version"

module Fledge
  # Finds the runtime archive for each platform you build for.
  #
  # A runtime is a launcher and a relocatable Ruby, built once per
  # platform by Fledge's own CI and attached to the GitHub Release of
  # the Fledge version that built it (ADR 001, section 2). You should
  # not need a Mac to build for macOS, so <tt>fledge build</tt> cannot
  # build runtimes itself; it has to fetch them. Fetching on every build
  # would be slow, and Fledge's own CI builds apps from runtimes that no
  # release holds yet.
  #
  # This class looks in three places, in order. When the environment
  # variable +FLEDGE_RUNTIME_DIR+ names a folder, the runtime comes from
  # there and nowhere else, which is how CI and Fledge's own development
  # build apps from runtimes they just built. Otherwise it looks in a
  # cache (<tt>$XDG_CACHE_HOME/fledge/runtimes</tt>, or
  # <tt>~/.cache/fledge/runtimes</tt>), and if the runtime is not there,
  # it downloads it from this version's GitHub Release into the cache,
  # checked against the release's +SHA256SUMS+.
  #
  # Use it to get the archive Fledge::Assembly copies an app into.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   runtimes = Fledge::Runtimes.new
  #   runtimes.archive(Fledge::Platform.find("x86_64-linux"))
  #   # => "/home/you/.cache/fledge/runtimes/fledge-runtime-0.0.0-x86_64-linux.tar.gz"
  #
  #   runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => "tmp/runtime" })
  #   runtimes.archive(Fledge::Platform.find("arm64-darwin"))
  #   # => "/path/to/tmp/runtime/fledge-runtime-0.0.0-arm64-darwin.tar.gz"
  #--
  # SPDX-SnippetEnd
  #++
  class Runtimes
    # Where Fledge's GitHub Releases keep their assets.
    RELEASES = "https://github.com/setdef/Fledge/releases/download"

    # The extension of every runtime archive. Runtimes are .tar.gz on
    # every platform, Windows too, whatever a built app ships in: Fledge
    # reads them, not the person who runs the app.
    EXTENSION = Archive::TAR_GZ

    # The file name of the runtime archive for +platform+ at +version+
    # (default: this Fledge's version).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.file_name(Fledge::Platform.find("x86_64-linux"), version: "0.1.0")
    #   # => "fledge-runtime-0.1.0-x86_64-linux.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def self.file_name(platform, version: VERSION)
      "fledge-runtime-#{version}-#{platform}#{EXTENSION}"
    end

    # The file name of the runtime's build-only companion for +platform+
    # at +version+ (default: this Fledge's version): Ruby's C headers, and
    # on Windows its import library, which a runtime prunes because no
    # running app reads them, and which compiling a gem's extension
    # against the runtime's own Ruby needs (ADR 006). Its top folder is
    # the runtime's, so it unpacks over it. It never ships in an app.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.dev_file_name(Fledge::Platform.find("arm64-darwin"), version: "0.1.0")
    #   # => "fledge-runtime-0.1.0-arm64-darwin-dev.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def self.dev_file_name(platform, version: VERSION)
      "#{File.basename(file_name(platform, version:), EXTENSION)}-dev#{EXTENSION}"
    end

    # The file name of the NSIS compiler, +makensis+, for computers of the
    # platform +host+, at +version+ (default: this Fledge's version). NSIS
    # publishes makensis only for Windows, so Fledge's CI builds it from
    # NSIS's source for macOS and Linux and publishes each beside the
    # runtimes (ADR 009). It runs on the computer that builds an app, and
    # never ships in one: what an installer holds of NSIS is in the
    # Windows runtime.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.makensis_file_name(Fledge::Platform.find("x86_64-linux"), version: "0.1.0")
    #   # => "fledge-makensis-0.1.0-x86_64-linux.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def self.makensis_file_name(host, version: VERSION)
      "fledge-makensis-#{version}-#{host}#{EXTENSION}"
    end

    # Creates the finder.
    #
    # [env] The environment to read +FLEDGE_RUNTIME_DIR+,
    #       +XDG_CACHE_HOME+, and +HOME+ from (default: +ENV+).
    # [release_url] Where this version's runtimes download from
    #               (default: its GitHub Release).
    # [log] Where to say that a download is starting, or +nil+.
    def initialize(env: ENV, release_url: "#{RELEASES}/v#{VERSION}", log: nil)
      @env = env
      @release_url = release_url
      @log = log
    end

    # The path of the runtime archive for +platform+, downloading it
    # into the cache first if it is not there. Raises Fledge::Error when
    # it cannot be found or downloaded.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.new.archive(Fledge::Platform.local)
    #--
    # SPDX-SnippetEnd
    #++
    def archive(platform)
      find(self.class.file_name(platform))
    end

    # The path of the build-only companion of +platform+'s runtime
    # (Runtimes.dev_file_name), found and downloaded as #archive finds and
    # downloads the runtime. Raises Fledge::Error when it cannot be found
    # or downloaded.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.new.dev_archive(Fledge::Platform.local)
    #   # => "/home/you/.cache/fledge/runtimes/fledge-runtime-0.0.0-x86_64-linux-dev.tar.gz"
    #--
    # SPDX-SnippetEnd
    #++
    def dev_archive(platform)
      find(self.class.dev_file_name(platform))
    end

    # The path of the NSIS compiler for computers of the platform +host+,
    # unpacked once into a folder beside its archive
    # (Runtimes.makensis_file_name), which is found and downloaded as
    # #archive finds and downloads a runtime. Raises Fledge::Error when it
    # cannot be found or downloaded.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.new.makensis(Fledge::Platform.local)
    #   # => "/home/you/.cache/fledge/runtimes/fledge-makensis-0.0.0-x86_64-linux/makensis"
    #--
    # SPDX-SnippetEnd
    #++
    def makensis(host)
      archive = find(self.class.makensis_file_name(host))
      top = File.basename(archive, EXTENSION)
      folder = File.join(cache, top)
      program = File.join(folder, host.executable("makensis"))
      return program if File.file?(program) && File.mtime(program) >= File.mtime(archive)

      unpack(archive, top, folder)
      program
    end

    private def unpack(archive, top, folder)
      FileUtils.rm_rf(folder)
      tops = Archive.names(archive).map { |name| name.split("/", 2).first }.uniq
      raise Error, "#{archive} is not Fledge's makensis: it holds #{tops.join(', ')}, not #{top}/" unless tops == [top]

      Archive.unpack(archive, into: File.dirname(folder))
    end

    private def find(name)
      directory = @env["FLEDGE_RUNTIME_DIR"].to_s
      return from_directory(directory, name) unless directory.empty?

      cached = File.join(cache, name)
      File.file?(cached) ? cached : download(name, cached)
    end

    # The folder downloaded runtimes are kept in.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Runtimes.new(env: { "HOME" => "/home/you" }).cache
    #   # => "/home/you/.cache/fledge/runtimes"
    #--
    # SPDX-SnippetEnd
    #++
    def cache
      base = @env["XDG_CACHE_HOME"].to_s
      base = File.join(@env["HOME"] || Dir.home, ".cache") if base.empty?
      File.join(File.expand_path(base), "fledge", "runtimes")
    end

    private def from_directory(directory, name)
      path = File.join(File.expand_path(directory), name)
      return path if File.file?(path)

      raise Error, "FLEDGE_RUNTIME_DIR is #{directory}, which has no #{name}"
    end

    private def download(name, destination)
      sums_url = "#{@release_url}/SHA256SUMS"
      @log&.puts "Downloading #{name} from #{@release_url}"
      Download.save("#{@release_url}/#{name}", to: destination, sha256: pinned_sha256(sums_url, name))
    end

    private def pinned_sha256(sums_url, name)
      Download.read(sums_url).each_line do |line|
        sha256, file = line.split(" ", 2)
        return sha256.to_s if file.to_s.strip.delete_prefix("*") == name
      end
      raise Error, "#{sums_url} lists no #{name}"
    end
  end
end
