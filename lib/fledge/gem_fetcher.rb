# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require "rubygems"
require "uri"
require_relative "download"

module Fledge
  # Finds the <tt>.gem</tt> file of a locked gem, for any platform.
  #
  # A build needs the very build of each gem the lockfile locks for its
  # target, which Bundler on the developer's computer may never have
  # installed. RubyGems.org serves every
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
  # the same way, with the mirror and the login Bundler's settings give
  # that server (Fledge::Bundle resolves them as Bundler does).
  #
  # Use it to get the files Fledge::GemPackage unpacks into an app.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   fetcher = Fledge::GemFetcher.new(cache: File.expand_path("~/.cache/fledge/gems"), project: "examples/my_cool_app")
  #   fetcher.fetch(locked_gem) # => "/home/you/.cache/fledge/gems/sqlite3-2.10.2-x64-mingw-ucrt.gem"
  #--
  # SPDX-SnippetEnd
  #++
  class GemFetcher
    # The servers that answer 403 for a gem file they do not have, and need
    # no login for any file they have: RubyGems.org, whose files come from
    # a storage bucket that answers 403 (AccessDenied) for a name it does
    # not hold (doc/contributors/design/gems.md, "Fetching a gem's file").
    PUBLIC_SERVERS = ["rubygems.org"].freeze

    # The hosts whose 403 to a request without a login means they have no
    # such file.
    attr_reader :public_servers

    # Creates the fetcher.
    #
    # [cache] Fledge's own folder of downloaded gems.
    # [project] The app's root, whose <tt>vendor/cache</tt> it looks in.
    # [gem_path] The folders whose <tt>cache</tt> it looks in (default:
    #            RubyGems' path).
    # [log] Where to say that a download is starting or trying again, or
    #       +nil+.
    # [public_servers] The hosts whose 403 to a request without a login
    #                  means they have no such file (default:
    #                  PUBLIC_SERVERS).
    # [waits] The seconds to wait before each try again of a download
    #         that failed for a moment (default: Download::WAITS).
    def initialize(cache:, project:, gem_path: Gem.path, log: nil, public_servers: PUBLIC_SERVERS, waits: Download::WAITS)
      @cache = cache
      @project = project
      @gem_path = gem_path
      @log = log
      @public_servers = public_servers
      @waits = waits
    end

    # The path of a <tt>.gem</tt> file for +gem+ (a Fledge::LockedGem)
    # whose SHA-256 is the lockfile's. Raises Fledge::Error when it cannot
    # be found or downloaded.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
      Download.save(gem.url, to: cached, sha256: gem.sha256, credentials: gem.credentials, waits: @waits, log: @log)
    rescue Download::Missing => e
      raise Error, missing(gem, e.status)
    rescue Download::Refused => e
      raise Error, forbids_only_what_it_lacks?(gem, e) ? missing(gem, e.status) : refused(gem, e)
    end

    # Whether +error+, a 403 from a public server that was sent no login,
    # means only that the server has no such file.
    private def forbids_only_what_it_lacks?(gem, error)
      error.status == 403 && !gem.credentials && @public_servers.include?(URI(gem.remote).host.to_s.downcase)
    end

    # What to do when the gem's server has no file for it: bring the file,
    # or lock the gem to the source that has it.
    private def missing(gem, status)
      "#{gem} comes from #{gem.remote}, which has no #{gem.file_name} (it answered #{status}). Put that file in the project's " \
        "vendor/cache, as bundle cache --all-platforms does, or point the Gemfile at the source that has it and run bundle lock, " \
        "then build again."
    end

    # What to do when the gem's server wanted a login, or refused the one
    # Bundler's settings gave: set it as Bundler reads it.
    private def refused(gem, error)
      host = URI(gem.remote).host.to_s
      "#{gem} comes from #{gem.remote}, which answered #{error.status} for it, " + if gem.credentials
        "and Bundler's login for #{host} was refused. Check it with bundle config get #{host}, or set it with " \
          "bundle config set --local #{host} USER:PASSWORD, then build again."
      else
        "and there is no login for it. Set one as Bundler reads it: bundle config set --local #{host} USER:PASSWORD " \
          "(or the environment variable BUNDLE_#{host.upcase.gsub('-', '___').gsub('.', '__')}), then build again."
      end
    end

    private def candidates(gem, cached)
      [File.join(@project, "vendor", "cache", gem.file_name), *@gem_path.map { |folder| File.join(folder, "cache", gem.file_name) }, cached]
    end
  end
end
