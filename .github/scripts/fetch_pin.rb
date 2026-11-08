# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileComment: Adapted from .github/scripts/fetch_pin.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
#++

# Downloads one input runtime/sources.yml pins, checked against its
# SHA-256, into tmp/downloads, and prints where it is. When the pin's url
# fails, each of its mirrors is tried in order, checked against the same
# SHA-256. Exits nonzero, printing nothing on standard output, when none
# serves the file, so a caller that assigns the path to a variable stops
# there.
#
#   ruby .github/scripts/fetch_pin.rb KEY...
#
# KEY... is the path to the pin in sources.yml, such as
# "ruby platforms x86_64-linux" or "replaceability musl".
require_relative "../../tasks/runtime_builder"

pin = RuntimeBuilder.new.sources.dig(*ARGV) or abort "no pin at #{ARGV.join(' ')} in runtime/sources.yml"
out = $stdout
$stdout = $stderr
begin
  out.puts RuntimeBuilder.new.fetch(pin.fetch("url"), pin.fetch("sha256"), mirrors: pin.fetch("mirrors", []))
rescue Fledge::Error => e
  abort "fetch_pin: #{e.message}"
end
