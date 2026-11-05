# frozen_string_literal: true

# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

# Experiment only (experiment/drag-to-fuse): a Lota-shaped game. It
# reports where it runs from and reads an asset beside it, as a game
# reads its images, through __dir__.
require "json"
require "tmpdir"
require_relative "lib/rules"

report = ARGV.fetch(0) { File.join(Dir.tmpdir, "spike_game.json") }
facts = {
  "game" => Rules.title,
  "file" => __FILE__,
  "dir" => __dir__,
  "argv" => ARGV,
  "asset" => File.read(File.join(__dir__, "assets", "hello.txt")).strip,
  "ruby" => RUBY_VERSION,
  "rubyopt" => ENV.fetch("RUBYOPT", nil),
}
File.write(report, "#{JSON.generate(facts)}\n")
