# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runtimes take minutes to build and download a hundred megabytes, so
# rake runtime stays out of the gate; CI runs it on each platform's own
# runner, and the Windows one on Linux (ci.yml), and
# test/built_app_test.rb runs what it builds. With a PLATFORM, it builds
# that platform's runtime, which works for Windows from macOS or Linux.
desc "Build this computer's runtime, or PLATFORM's, into tmp/runtime (runtime/sources.yml pins its inputs)"
task :runtime, [:platform] do |_task, arguments|
  require_relative "runtime_builder"
  platform = arguments[:platform] ? RuntimeBuilder.platform(arguments[:platform]) : Fledge::Platform.local
  RuntimeBuilder.new(platform:).call
end

namespace :runtime do
  # The first step of a release (ADR 014; AGENTS.md, Releasing): with the
  # release commit pushed and its CI green, this downloads the runtimes
  # that CI run built (by default the latest successful push run of
  # ci.yml on HEAD) with the GitHub CLI and pins their SHA-256s in
  # lib/fledge/SHA256SUMS, for a commit of their own that is then tagged.
  desc "Pin the runtimes CI run RUN built (default: HEAD's) in lib/fledge/SHA256SUMS, before tagging a release"
  task :pin, [:run] do |_task, arguments|
    require_relative "runtime_pins"
    head = `git rev-parse HEAD`.strip
    run = arguments[:run] || `gh run list --workflow ci.yml --commit #{head} --event push --status success --json databaseId --jq '.[0].databaseId'`.strip
    abort "❌ No successful CI run of #{head} to pin the runtimes of; push it and wait for CI" if run.empty?

    work = File.join("tmp", "pins")
    FileUtils.rm_rf(work)
    sh "gh", "run", "download", run, "--pattern", "runtime-*", "--dir", work
    puts "Pinned run #{run}'s runtimes in #{RuntimePins.write(work)}"
  end
end
