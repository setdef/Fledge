# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "download"
require_relative "error"
require_relative "tar_gz"
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
    EXTENSION = TarGz::EXTENSION

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
      name = self.class.file_name(platform)
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
