# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "tmpdir"

# The gems a release would publish on RubyGems.org (ADR 030). Both tasks
# work offline and push nothing: a person pushes the gems by hand, from
# 1.0.0, with the checklist in doc/contributors/handoff.md (AGENTS.md,
# Releasing).
desc "Build the release's gems from ASSETS, a folder of the runtimes lib/fledge/SHA256SUMS pins, into OUT (default tmp/gems)"
task :gems, [:assets, :out] do |_task, arguments|
  require_relative "release_gems"
  assets = arguments[:assets] or abort "❌ Name the folder of the release's assets: rake \"gems[ASSETS]\""
  out = arguments[:out] || File.join("tmp", "gems")
  FileUtils.rm_rf(out)
  built = ReleaseGems.build(assets:, out:)
  built.each { |path| puts format("%12d  %s", File.size(path), path) }
  puts "✅ #{built.size} gems in #{out}, their SHA-256s in #{File.join(out, 'SHA256SUMS')}"
rescue ReleaseGems::Mismatch => e
  abort "❌ #{e.message}"
end

namespace :gems do
  # A developer's first steps with the gems, with no network, twice: with
  # RubyGems, fledge and this computer's runtime gem from DIR into an
  # empty GEM_HOME; and with Bundler, a project whose Gemfile names fledge
  # and whose vendor/cache holds every gem in DIR, installed with bundle
  # install --local, which picks this computer's runtime gem as it would
  # from RubyGems.org. Each then runs fledge --version and builds
  # examples/hello with an empty cache and every download sent to a
  # closed port, so the runtime can come only from the installed gem, and
  # the built hello runs with an environment that has no Ruby in it.
  # Nothing of the caller's Ruby environment or Bundler reaches either.
  desc "Install the gems in DIR (default tmp/gems) with RubyGems and with Bundler, and build and run hello from each offline"
  task :check, [:dir] do |_task, arguments|
    require_relative "gems_check"
    dir = File.expand_path(arguments[:dir] || File.join("tmp", "gems"))
    Bundler.with_unbundled_env { GemsCheck.new(dir:, log: $stdout).call }
    puts "✅ fledge #{Fledge::VERSION} and its runtime for #{Fledge::Platform.local} install from #{dir} with RubyGems " \
      "and with Bundler, and build and run hello offline"
  rescue GemsCheck::Failure => e
    abort "❌ #{e.message}"
  end
end
