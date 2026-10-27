# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "rubygems"
require_relative "download"

module Fledge
  # Finds the <tt>.gem</tt> file of a locked gem, for any platform.
  #
  # Building for Windows on a Mac needs Windows' build of each native gem,
  # which Bundler never installs on the Mac. RubyGems.org serves every
  # platform's <tt>.gem</tt> file at <tt>/gems/FILE</tt>, as
  # <tt>gem fetch --platform</tt> fetches it, and the Gemfile.lock records
  # each one's SHA-256, so any copy can be checked against the lockfile.
  #
  # This class looks first where a developer may already have the file:
  # the project's <tt>vendor/cache</tt>, where <tt>bundle cache
  # --all-platforms</tt> keeps every platform's, then the cache of each
  # folder in RubyGems' path, then Fledge's own cache
  # (<tt>$XDG_CACHE_HOME/fledge/gems</tt>, or <tt>~/.cache/fledge/gems</tt>).
  # It uses a copy only if its SHA-256 is the lockfile's, and otherwise
  # downloads the file from the gem's server into its own cache, checked
  # the same way.
  #
  # Use it to get the files Fledge::GemPackage unpacks into an app.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   fetcher = Fledge::GemFetcher.new(cache: File.expand_path("~/.cache/fledge/gems"), project: "examples/my_cool_app")
  #   fetcher.fetch(locked_gem) # => "/home/you/.cache/fledge/gems/sqlite3-2.10.2-x64-mingw-ucrt.gem"
  #--
  # SPDX-SnippetEnd
  #++
  class GemFetcher
    # Creates the fetcher.
    #
    # [cache] Fledge's own folder of downloaded gems.
    # [project] The app's root, whose <tt>vendor/cache</tt> it looks in.
    # [gem_path] The folders whose <tt>cache</tt> it looks in (default:
    #            RubyGems' path).
    # [log] Where to say that a download is starting, or +nil+.
    def initialize(cache:, project:, gem_path: Gem.path, log: nil)
      @cache = cache
      @project = project
      @gem_path = gem_path
      @log = log
    end

    # The path of a <tt>.gem</tt> file for +gem+ (a Fledge::LockedGem)
    # whose SHA-256 is the lockfile's. Raises Fledge::Error when it cannot
    # be found or downloaded.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   fetcher.fetch(locked_gem) # => "/path/to/project/vendor/cache/i18n-1.15.2.gem"
    #--
    # SPDX-SnippetEnd
    #++
    def fetch(gem)
      cached = File.join(@cache, gem.file_name)
      found = candidates(gem, cached).find { |path| File.file?(path) && Digest::SHA256.file(path).hexdigest == gem.sha256 }
      return found if found

      @log&.puts "Downloading #{gem.file_name} from #{gem.remote}"
      Download.save(gem.url, to: cached, sha256: gem.sha256)
    end

    private def candidates(gem, cached)
      [File.join(@project, "vendor", "cache", gem.file_name), *@gem_path.map { |folder| File.join(folder, "cache", gem.file_name) }, cached]
    end
  end
end
