# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

# Experiment only (experiment/build-from): an app that builds the
# project ARGV[0] into the folder ARGV[1] from itself, with the fledge
# its Gemfile ships as an ordinary gem, as a framework's app would (ADR
# 032, section 4): fledge build --from, run through the executable
# RubyGems wrote into Gem.bindir (ADR 020, section 6).
#
# The person's own RUBYOPT and RUBYLIB reach a child Ruby as under
# bundle exec, where Bundler records them as BUNDLER_ORIG_*; fledge is
# the app's, so it gets only the app's Bundler setup.
app = File.dirname(__dir__)
fledge = File.join(Gem.bindir, Gem.win_platform? ? "fledge.bat" : "fledge")
puts "fledge: #{fledge} (#{File.file?(fledge) ? 'present' : 'missing'})"
puts "app: #{app}"
child = { "RUBYOPT" => "-rbundler/setup", "RUBYLIB" => nil }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
ok = system(child, fledge, "build", "--from", app, "-o", ARGV.fetch(1), ARGV.fetch(0))
puts format("fledge build --from took %.2f s and %s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, ok ? "succeeded" : "failed (#{$?.inspect})")
exit(ok ? 0 : 1)
