# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# The console probe: an app that waits to be interrupted.
#
# Ctrl-C in a terminal, closing it, and the console's code page reach an
# app through the operating system and Ruby, and Fledge's launcher must
# stand in none of their way: a built app must end as ruby main.rb ends,
# through Ruby's own handlers, with the same exit status (ADR 081;
# doc/contributors/design/parity.md, "Console checks").
# .github/scripts/deliver-console.sh and deliver-console.ps1 run this
# app, built and as ruby main.rb, in a terminal or console of their own,
# interrupt it, and compare what it recorded with what Ruby does.
#
#   main.rb LOG
#
# It prints a line outside ASCII to its terminal, which the scripts read
# back from the terminal, records the locale's character set and the
# encoding Ruby chose for it, and "ready", in LOG, and sleeps. Whatever ends the sleep, it records the
# exception that did in its ensure clause, and "at_exit ran" from its
# at_exit hook, as an app that cleans up on the way out does.

$stdout.sync = true
log = File.open(ARGV.fetch(0), "a")
log.sync = true
at_exit { log.puts "at_exit ran" }

puts "café ✓"
log.puts "locale #{Encoding.locale_charmap}"
log.puts "external #{Encoding.default_external}"
log.puts "ready"
begin
  sleep 120
ensure
  log.puts "ensure ran (#{$!.class}: #{$!&.message})"
end
