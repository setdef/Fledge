# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Runtimes take minutes to build and download a hundred megabytes, so
# rake runtime stays out of the gate; CI runs it on each platform's own
# runner (ci.yml), and test/built_app_test.rb runs what it builds.
desc "Build this computer's runtime into tmp/runtime (runtime/sources.yml pins its inputs)"
task :runtime do
  require_relative "runtime_builder"
  RuntimeBuilder.new.call
end
