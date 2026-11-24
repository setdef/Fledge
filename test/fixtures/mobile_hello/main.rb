# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

# What the mobile runtimes promise an app, in one line (ADR 099): json, a
# default gem, and csv, a bundled gem that RubyGems activates as a gem;
# prism, a bundled gem whose extension compiles its own libprism beside
# the one libruby holds (doc/contributors/design/phone-runtimes.md,
# "Bundled gems' extensions"), parsing with its extension; and HTTPS,
# which needs the CA certificates the runtime carries: a server on the
# computer that runs the check, whose certificate a test authority signed,
# which the check appended to the runtime's certificates in the app
# (MobileParity::HTTPS), refused with an empty trust store and answered
# with the runtime's, so that the line shows OpenSSL read the file the
# runtime carries, and reaches nothing beyond the computer;
# and YJIT, where the runtime has it (Android's, as a desktop's; iOS
# lets an app write no code it then runs), enabled as Rails enables it,
# compiling a method it calls often enough into machine code.
# tasks/mobile_parity.rb builds it as an app with fledge build ios and
# fledge build android, runs it on each phone, and checks the line.
require "json"
require "csv"
require "prism"
require "net/http"
require "openssl"

# The Simulator shares the computer's network, so the check gives the
# app the address of its server in the environment; an Android emulator
# reaches the server through adb reverse, at this port on its own
# loopback.
uri = URI(ENV.fetch("FLEDGE_PARITY_HTTPS_URL", "https://127.0.0.1:18443/ok.http"))
get = lambda do |store|
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = http.read_timeout = 20
  http.cert_store = store if store
  http.start { |connection| connection.get(uri.path).code }
end
untrusted = begin
  get.call(OpenSSL::X509::Store.new)
  "connected"
rescue OpenSSL::SSL::SSLError => e
  e.message[/certificate verify failed/] || e.message
end
status = get.call(nil)
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
  "over HTTPS: #{untrusted} with an empty trust store, #{status} with the runtime's CA certificates, #{jit}"

# A NUL byte in what an app prints reaches the log whole, not cutting the
# entry short (runtime/mobile/output.c, log_line).
puts "NUL: before\0after"
