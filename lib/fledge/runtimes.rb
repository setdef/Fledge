# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
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
  # it downloads it from this version's GitHub Release into the cache.
  # When +FLEDGE_RUNTIME_MIRROR+ names a base URL, the download comes
  # from there instead, as <tt>MIRROR/vVERSION/NAME</tt>, the path the
  # release has under <tt>https://github.com/setdef/Fledge/releases/download</tt>,
  # and from nowhere else: a mirror that lacks a file fails the build
  # rather than sending it to a host its owner chose to avoid.
  #
  # Either way, a runtime from the cache or a download must have the
  # SHA-256 this gem pins for it in +PINS+, which the release workflow
  # wrote from the very runtimes it then published (ADR 014). The
  # release's own +SHA256SUMS+ catches a damaged download, but a release
  # whose assets and sums were both replaced would pass it; the pins were
  # fixed when this gem was, so it does not, and neither does a mirror
  # that serves other bytes.
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

    # The SHA-256 of every asset of this version's release, as
    # +sha256sum+ writes them, committed before the release was tagged
    # (ADR 014). The release's +SHA256SUMS+ is this file.
    PINS = File.join(File.dirname(__FILE__), "SHA256SUMS")

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
    # at +version+ (default: this Fledge's version): the library a gem's
    # extension links against (static libruby, or on Windows the import
    # library of Ruby's DLL), which a runtime prunes because no running
    # app reads it, and which compiling a gem's extension against the
    # runtime's own Ruby needs beside the headers the runtime holds (ADR
    # 006). Its top folder is
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

    # Creates the finder.
    #
    # [env] The environment to read +FLEDGE_RUNTIME_DIR+,
    #       +FLEDGE_RUNTIME_MIRROR+, +XDG_CACHE_HOME+, and +HOME+ from
    #       (default: +ENV+).
    # [release_url] Where this version's runtimes download from when no
    #               mirror is set (default: its GitHub Release).
    # [log] Where to say that a download is starting, or +nil+.
    # [pins] The file of SHA-256s to check runtimes against (default:
    #        PINS).
    def initialize(env: ENV, release_url: "#{RELEASES}/v#{VERSION}", log: nil, pins: PINS)
      @env = env
      @release_url = release_url
      @log = log
      @pins = pins
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

    private def find(name)
      directory = @env["FLEDGE_RUNTIME_DIR"].to_s
      return from_directory(directory, name) unless directory.empty?

      sha256 = pin(name)
      cached = File.join(cache, name)
      return cached if File.file?(cached) && pinned?(cached, sha256)

      download(name, cached, sha256)
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

    private def pinned?(cached, sha256)
      return true if Digest::SHA256.file(cached).hexdigest == sha256

      @log&.puts "#{cached} does not match the SHA-256 this Fledge pins for it; downloading it again"
      false
    end

    private def download(name, destination, sha256)
      mirror = @env["FLEDGE_RUNTIME_MIRROR"].to_s.sub(%r{/+\z}, "")
      return from_mirror(mirror, name, destination, sha256) unless mirror.empty?

      @log&.puts "Downloading #{name} from #{@release_url}"
      Download.save("#{@release_url}/#{name}", to: destination, sha256:)
    end

    # Downloads +name+ from the mirror, where this version's release
    # keeps it under the mirror's base: MIRROR/vVERSION/NAME. A mirror
    # that fails is not passed over for the release (ADR 031).
    private def from_mirror(mirror, name, destination, sha256)
      base = "#{mirror}/v#{VERSION}"
      @log&.puts "Downloading #{name} from #{base}"
      Download.save("#{base}/#{name}", to: destination, sha256:)
    rescue Download::Mismatch => e
      raise Error, "FLEDGE_RUNTIME_MIRROR is #{mirror}, whose #{name} has SHA-256 #{e.actual}, but Fledge #{VERSION} " \
        "pins #{e.expected} for it. The mirror does not hold the file this Fledge released; nothing was saved."
    rescue Error => e
      raise Error, "FLEDGE_RUNTIME_MIRROR is #{mirror}: #{e.message}"
    end

    private def pin(name)
      if File.file?(@pins)
        File.foreach(@pins, chomp: true) do |line|
          sha256, file = line.split(" ", 2)
          return sha256.to_s.downcase if file.to_s.strip.delete_prefix("*") == name
        end
      end
      raise Error, "Fledge #{VERSION} pins no SHA-256 for #{name}, so it is not a released Fledge and has no " \
        "runtimes to download. Install Fledge from a release tag, or set FLEDGE_RUNTIME_DIR to a folder of " \
        "runtimes you built (rake runtime)."
    end
  end
end
