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
  platform = arguments[:platform] ? Fledge::Platform.find(arguments[:platform]) : Fledge::Platform.local
  RuntimeBuilder.new(platform:).call
end
