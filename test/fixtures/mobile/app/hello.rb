# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# What the mobile runtimes promise an app, in one line (ADR 011): json, a
# default gem, and csv, a bundled gem that RubyGems activates as a gem,
# and HTTPS to rubygems.org, which needs the CA certificates the runtime
# carries. tasks/mobile_parity.rb runs it on each phone and checks the
# line.
require "json"
require "csv"
require "net/http"

status = Net::HTTP.start("rubygems.org", 443, use_ssl: true, open_timeout: 20, read_timeout: 20) { |http| http.head("/").code }
puts "Hello from Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}: " \
  "#{JSON.generate(CSV.parse_line("csv,#{Gem.loaded_specs.fetch('csv').version}"))} over HTTPS: #{status}"
