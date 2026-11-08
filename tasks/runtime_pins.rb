# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require "fileutils"
require_relative "runtime_builder"

# Pins a release's runtimes in the gem before the release is tagged
# (ADR 014), as Homebrew's brew pr-upload writes a formula's bottle
# hashes from the bottles CI built and then uploads those same bottles,
# and as uv commits the SHA-256 of every python-build-standalone build it
# downloads. Runtime builds are not reproducible, so the hashes can only
# come from the very files the release publishes: CI builds them on the
# release commit, this writes their SHA-256s into lib/fledge/SHA256SUMS
# in the next commit, which is tagged, and release.yml publishes the
# runtimes of the first commit's CI run once they match.
module RuntimePins
  # The assets found are not exactly the ones a release publishes.
  class Mismatch < StandardError; end

  # Writes the SHA-256 of every release asset of +version+ found in
  # +folder+ (or in the folders inside it, one per artifact) to +to+,
  # one sha256sum line each, sorted by name. Raises Mismatch, and writes
  # nothing, unless the assets are exactly RuntimeBuilder.release_assets.
  def self.write(folder, to: Fledge::Runtimes::PINS, version: Fledge::VERSION)
    found = Dir.glob("**/*", base: folder).select { |path| File.file?(File.join(folder, path)) }
    by_name = found.to_h { |path| [File.basename(path), File.join(folder, path)] }
    check(by_name.keys, RuntimeBuilder.release_assets(version:))

    lines = by_name.keys.sort.map { |name| "#{Digest::SHA256.file(by_name.fetch(name)).hexdigest}  #{name}\n" }
    File.write(to, lines.join)
    to
  end

  def self.check(found, expected)
    missing = expected - found
    unexpected = found - expected
    return if missing.empty? && unexpected.empty?

    raise Mismatch, "The assets are not the release's (missing: #{missing.join(', ')}; unexpected: #{unexpected.join(', ')})"
  end
end
