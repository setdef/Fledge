# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# makensis builds from NSIS's source in a minute and needs Python, so
# rake makensis stays out of the gate, as rake runtime does; CI runs it on
# each platform's own runner (ci.yml). With a HOST, it builds that
# computer's, which for x64-mingw-ucrt is the NSIS release's own
# makensis.exe, repacked on any computer.
desc "Build this computer's makensis, or HOST's, into tmp/makensis (runtime/sources.yml pins NSIS)"
task :makensis, [:host] do |_task, arguments|
  require_relative "makensis_builder"
  host = arguments[:host] ? Fledge::Platform.find(arguments[:host]) : Fledge::Platform.local
  MakensisBuilder.new(host:).call
end
