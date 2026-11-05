# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

# Experiment only (experiment/file-associations): an app that builds the
# project ARGV[0] into the folder ARGV[1] from itself, with the fledge
# its Gemfile ships as an ordinary gem and the tools its fledge.yml's
# build_tools put in it (ADR 032, section 4): fledge build --from, run
# through the executable RubyGems wrote into Gem.bindir. The person's
# own RUBYOPT and RUBYLIB stay out of the child, as ADR 032, section 8,
# says a framework does.
app = File.dirname(__dir__)
fledge = File.join(Gem.bindir, Gem.win_platform? ? "fledge.bat" : "fledge")
child = { "RUBYOPT" => "-rbundler/setup", "RUBYLIB" => nil }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ok = system(child, fledge, "build", "--from", app, "-o", ARGV.fetch(1), ARGV.fetch(0))
puts format("fledge build --from took %.2f s and %s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, ok ? "succeeded" : "failed (#{$?.inspect})")
exit(ok ? 0 : 1)
