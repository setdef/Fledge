# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# What the mobile runtimes promise an app, in one line (ADR 011): json, a
# default gem, and csv, a bundled gem that RubyGems activates as a gem;
# prism, a bundled gem whose extension compiles its own libprism beside
# the one libruby holds (ADR 067), parsing with its extension; and HTTPS
# to rubygems.org, which needs the CA certificates the runtime carries;
# and YJIT, where the runtime has it (Android's, as a desktop's; iOS
# lets an app write no code it then runs), enabled as Rails enables it,
# compiling a method it calls often enough into machine code.
# tasks/mobile_parity.rb builds it as an app with fledge build ios and
# fledge build android, runs it on each phone, and checks the line.
require "json"
require "csv"
require "prism"
require "net/http"
require "timeout"

# An emulator's network drops a connection now and then, so a dropped or
# stalled connection is tried again, at most three times, each bounded;
# a certificate that does not verify is never retried, since that is
# what this line checks.
attempts = 0
begin
  attempts += 1
  status = Timeout.timeout(60) do
    Net::HTTP.start("rubygems.org", 443, use_ssl: true, open_timeout: 20, read_timeout: 20) { |http| http.head("/").code }
  end
rescue SystemCallError, IOError, SocketError, Timeout::Error => e
  raise if attempts == 3

  warn "hello.rb: #{e.class}: #{e.message}; trying again"
  sleep 5
  retry
end
def fib(number) = (number < 2) ? number : fib(number - 1) + fib(number - 2)

jit = if defined?(RubyVM::YJIT)
  RubyVM::YJIT.enable
  before = RubyVM::YJIT.runtime_stats.fetch(:inline_code_size)
  value = fib(20)
  written = RubyVM::YJIT.runtime_stats.fetch(:inline_code_size) - before
  "YJIT #{RubyVM::YJIT.enabled? ? 'on' : 'off'}: fib(20) is #{value} in #{written} bytes of machine code"
else
  "no YJIT"
end
puts "Hello from Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}: " \
  "#{JSON.generate(CSV.parse_line("csv,#{Gem.loaded_specs.fetch('csv').version}"))}, " \
  "prism #{Gem.loaded_specs.fetch('prism').version} parses 1 + 2 as #{Prism.parse('1 + 2').value.statements.body.first.name}, " \
  "over HTTPS: #{status}, #{jit}"
