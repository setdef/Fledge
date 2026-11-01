# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/runtime_pins"
require "digest"

# How a release's runtimes come to be pinned in the gem before its tag
# (ADR 014): rake runtime:pin writes lib/fledge/SHA256SUMS from the
# runtimes one CI run built, which release.yml then publishes.
class RuntimePinsTest < Minitest::Test
  def test_pins_every_release_asset_by_sha256_in_sha256sums_form
    Dir.mktmpdir do |dir|
      assets = write_assets(dir, "1.2.3")
      pins = File.join(dir, "SHA256SUMS")

      RuntimePins.write(File.join(dir, "assets"), to: pins, version: "1.2.3")

      expected = assets.sort.map { |name| "#{Digest::SHA256.hexdigest(name)}  #{name}\n" }.join
      assert_equal expected, File.read(pins)
    end
  end

  # Assets gathered from several artifacts land in a folder each, as
  # gh run download writes them.
  def test_finds_assets_in_the_folders_of_the_artifacts_they_came_in
    Dir.mktmpdir do |dir|
      assets = write_assets(dir, "1.2.3")
      assets.each_with_index do |name, index|
        folder = File.join(dir, "assets", "runtime-#{index % 3}")
        FileUtils.mkdir_p(folder)
        File.rename(File.join(dir, "assets", name), File.join(folder, name))
      end

      RuntimePins.write(File.join(dir, "assets"), to: File.join(dir, "SHA256SUMS"), version: "1.2.3")

      assert_equal assets.sort, File.readlines(File.join(dir, "SHA256SUMS"), chomp: true).map { |line| line.split("  ").last }
    end
  end

  def test_refuses_assets_that_are_not_exactly_the_releases
    Dir.mktmpdir do |dir|
      assets = write_assets(dir, "1.2.3")
      File.delete(File.join(dir, "assets", assets.first))
      File.write(File.join(dir, "assets", "stray.txt"), "stray")
      pins = File.join(dir, "SHA256SUMS")

      error = assert_raises(RuntimePins::Mismatch) { RuntimePins.write(File.join(dir, "assets"), to: pins, version: "1.2.3") }
      assert_includes error.message, "missing: #{assets.first}"
      assert_includes error.message, "unexpected: stray.txt"
      refute_path_exists pins
    end
  end

  # What the gem ships pins one release's assets, each of them a name
  # Fledge still asks for. A platform added since that release has no
  # pins until the next, whose release.yml checks the pins are exactly
  # its assets.
  def test_the_shipped_pins_name_assets_of_one_release
    names = File.readlines(Fledge::Runtimes::PINS, chomp: true).map { |line| line.split("  ", 2).last }
    version = names.first[/\Afledge-runtime-(.+?)-(?:aarch64|x86_64|arm64|x64|ios|android)/, 1]

    assert_empty names - RuntimeBuilder.release_assets(version:)
    assert_operator names.size, :>=, 25
  end

  private def write_assets(dir, version)
    folder = File.join(dir, "assets")
    FileUtils.mkdir_p(folder)
    RuntimeBuilder.release_assets(version:).each { |name| File.write(File.join(folder, name), name) }
  end
end
