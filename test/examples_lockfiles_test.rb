# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Every example's Gemfile.lock holds a checksum for the Bundler its
# BUNDLED WITH names. CI builds every example on Windows, whose runtime
# carries another Bundler than the other desktops' Ruby 4.1.0-preview1,
# so there the app ships the lockfile's Bundler, and fledge build refuses
# a lockfile without its checksum. A lockfile written by a Ruby's own Bundler, a
# default gem, has none, and examples/lota_pop landed so; only the
# Windows Build jobs said so, an hour after the push.
class ExamplesLockfilesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_examples_lockfile_has_a_checksum_for_the_bundler_it_names
    lockfiles = Dir.glob(File.join(ROOT, "examples", "*", "Gemfile.lock"))
    refute_empty lockfiles

    missing = lockfiles.filter_map do |path|
      text = File.read(path)
      version = text[/^BUNDLED WITH\r?\n\s+(\S+)/, 1] or next
      relative = path.delete_prefix("#{ROOT}/")
      "#{relative}: bundler (#{version})" unless text.match?(/^  bundler \(#{Regexp.escape(version)}\) sha256=\h{64}\r?$/)
    end

    assert_empty missing, "lockfiles under examples/ with no checksum for their Bundler: run gem install bundler -v VERSION, " \
      "then bundle lock --add-checksums"
  end
end
