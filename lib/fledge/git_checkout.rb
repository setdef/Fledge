# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require "open3"
require_relative "error"

module Fledge
  # Fetches a git gem's repository at the revision its lockfile locks.
  #
  # Bundler fetches a git gem into a bare cache of the repository, then
  # clones that cache and checks out the locked revision where the gem
  # is installed, and evaluates every gemspec there, writing each back as
  # Ruby that needs neither git nor anything else to load
  # (Bundler::Source::Git#checkout and #serialize_gemspecs_in, at Bundler
  # 4.0.20). A built app's Bundler reads those gemspecs, with no git on
  # the computer it runs on.
  #
  # This class does the same: it keeps a bare clone of each repository in
  # Fledge's cache (<tt>~/.cache/fledge/git</tt>), fetches only when the
  # locked commit is not there, refuses a commit the repository does not
  # hold, checks the commit out into a work folder, and evaluates its
  # gemspecs as Bundler does. One checkout serves every gem the lockfile
  # takes from that repository at that revision.
  #
  # Use it for each git gem an app ships (Fledge::GitPackage).
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   checkouts = Fledge::GitCheckout.new(cache: File.expand_path("~/.cache/fledge/git"), work: Dir.mktmpdir)
  #   checkouts.checkout(git_gem) # => "/tmp/d20261027-1-x/git/Ferro-21a106d0c0d6"
  #--
  # SPDX-SnippetEnd
  #++
  class GitCheckout
    # What git reads from the environment that would point it at another
    # repository, or stop to ask for a password no one is there to type.
    ENVIRONMENT = { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil, "GIT_TERMINAL_PROMPT" => "0" }.freeze

    # Creates the fetcher.
    #
    # [cache] Where bare clones of repositories are kept between builds.
    # [work] The build's own folder, where checkouts go.
    # [log] Where to say that a fetch is starting, or +nil+.
    def initialize(cache:, work:, log: nil)
      @cache = cache
      @work = work
      @log = log
      @checkouts = {} # : Hash[[String, String], String]
    end

    # The folder holding +gem+'s repository (a Fledge::GitGem) at its
    # revision, with its gemspecs evaluated. Raises Fledge::Error when git
    # is missing, the repository cannot be fetched, or it holds no such
    # commit.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   File.exist?(File.join(checkouts.checkout(git_gem), "gems/idna/ferro-idna.gemspec")) # => true
    #--
    # SPDX-SnippetEnd
    #++
    def checkout(gem)
      @checkouts[[gem.uri, gem.revision]] ||= begin
        mirror = mirror(gem)
        folder = File.join(@work, "git", gem.scope)
        FileUtils.rm_rf(folder)
        FileUtils.mkdir_p(File.dirname(folder))
        git("clone", "--quiet", "--no-checkout", "--", mirror, folder)
        git("-C", folder, "checkout", "--quiet", "--detach", gem.revision)
        serialize_gemspecs(folder, gem.glob)
        folder
      end
    end

    # The bare clone of +gem+'s repository in the cache, holding its
    # revision.
    private def mirror(gem)
      path = File.join(@cache, "#{gem.scope.delete_suffix("-#{gem.revision[0, 12]}")}-#{Digest::SHA256.hexdigest(gem.uri)[0, 16]}.git")
      unless File.directory?(path)
        @log&.puts "Fetching #{gem.uri}"
        FileUtils.mkdir_p(@cache)
        git("clone", "--quiet", "--bare", "--", gem.uri, path)
      end
      fetch(gem, path) unless commit?(path, gem.revision)
      return path if commit?(path, gem.revision)

      raise Error, "#{gem.uri} holds no commit #{gem.revision}, which the lockfile locks for #{gem}. Run bundle lock, then build again."
    end

    # Fetches every branch and tag, then the commit itself, which a server
    # may serve though no branch holds it any more.
    private def fetch(gem, path)
      @log&.puts "Fetching #{gem.uri}"
      git("-C", path, "fetch", "--quiet", "--force", "origin", "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*")
      git("-C", path, "fetch", "--quiet", "origin", gem.revision) unless commit?(path, gem.revision)
    rescue Error
      nil
    end

    private def commit?(path, revision)
      _, status = Open3.capture2e(ENVIRONMENT, "git", "-C", path, "cat-file", "-e", "#{revision}^{commit}")
      status.success?
    rescue SystemCallError
      false
    end

    #--
    # SPDX-SnippetBegin
    # SPDX-License-Identifier: MIT
    # SPDX-SnippetCopyrightText: 2010-2019 André Arko, 2009 Engine Yard
    # SPDX-SnippetComment: Bundler::Source::Git#serialize_gemspecs_in,
    #   adapted from bundler/source/git.rb at Bundler 4.0.20 (lines 321 to
    #   332).
    #++
    # Evaluates each gemspec +glob+ finds in +folder+ and writes it back as
    # the Ruby it evaluates to.
    private def serialize_gemspecs(folder, glob)
      require "bundler"
      Dir.glob(glob, base: folder).each do |relative|
        path = File.join(folder, relative)
        spec = Bundler.load_gemspec(path) or next
        spec.installed_by_version = Gem::VERSION
        File.binwrite(path, spec.to_ruby)
      end
    end
    #--
    # SPDX-SnippetEnd
    #++

    private def git(*arguments)
      out, status = Open3.capture2e(ENVIRONMENT, "git", *arguments)
      raise Error, "git #{arguments.join(' ')} failed:\n#{out}" unless status.success?

      out
    rescue SystemCallError => e
      raise Error, "Fledge needs git on PATH to fetch the app's gems from git (#{e.message})"
    end
  end
end
