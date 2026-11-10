# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# Builds the project ARGV[0] into the folder ARGV[1] from the app
# ARGV[2], by default this app itself, with the fledge its Gemfile ships
# as an ordinary gem: fledge build --from, run through the executable
# RubyGems wrote into Gem.bindir, whose exit status becomes this app's.
# The person's own RUBYOPT and RUBYLIB stay out of the child, as
# doc/contributors/design/desktop-apps.md, "Building from a built app",
# says a framework does.
from = ARGV.fetch(2) { File.dirname(__dir__) }
fledge = File.join(Gem.bindir, Gem.win_platform? ? "fledge.bat" : "fledge")
child = { "RUBYOPT" => "-rbundler/setup", "RUBYLIB" => nil }
system(child, fledge, "build", "--from", from, "-o", ARGV.fetch(1), ARGV.fetch(0))
exit(Process.last_status.exitstatus || 1)
