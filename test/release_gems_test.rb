# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "../tasks/release_gems"
require "digest"
require "json"
require "rubygems/package"

# The gems a release would publish on RubyGems.org, built from its
# pinned assets (ADR 030): real .gem files, read back with RubyGems.
class ReleaseGemsTest < Minitest::Test
  VERSION = Fledge::VERSION
  DESKTOP = Fledge::Platform.names
  PHONES = Fledge::MobilePlatform.names

  def test_builds_a_runtime_gem_per_target_holding_its_assets_byte_for_byte_and_fledge_depending_on_it
    Dir.mktmpdir do |dir|
      assets = write_assets(dir)
      built = ReleaseGems.build(assets: File.join(dir, "assets"), out: File.join(dir, "gems"), pins: pins(dir, assets))

      names = built.map { |path| File.basename(path) }
      assert_equal [
        *DESKTOP.map { |target| "fledge-runtime-#{VERSION}-#{Fledge::RuntimeGem.new(target:).platform}.gem" },
        *PHONES.map { |phone| "fledge-runtime-#{phone}-#{VERSION}.gem" },
        "fledge-#{VERSION}.gem",
], names

      by_target = assets.group_by { |name, _| target_of(name) }
      [*DESKTOP, *PHONES].each_with_index do |target, index|
        package = Gem::Package.new(built[index])
        contents = gem_files(package)
        expected = by_target.fetch(target).to_h { |name, body| ["runtime/#{name}", body] }
        assert_equal expected, contents, target
        assert_equal ">= 4.0, < 4.1.dev", package.spec.required_ruby_version.to_s, target
        assert_equal "https://fledge.invalid", package.spec.metadata["allowed_push_host"]
        assert_equal %w[Apache-2.0 BSD-2-Clause MIT Ruby], package.spec.licenses
      end

      fledge = Gem::Package.new(built.last).spec
      assert_equal [["fledge-runtime", "= #{VERSION}"]], fledge.runtime_dependencies.map { |dependency| [dependency.name, dependency.requirement.to_s] }
      assert_equal "https://fledge.invalid", fledge.metadata["allowed_push_host"]
      assert_includes fledge.files, "lib/fledge/runtimes.rb"

      sums = File.readlines(File.join(dir, "gems", "SHA256SUMS"), chomp: true)
      assert_equal built.map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}" }.sort, sums
    end
  end

  # Anyone can build a release's gems again from its assets and compare.
  def test_the_same_assets_build_the_same_gems
    Dir.mktmpdir do |dir|
      assets = write_assets(dir)
      sums = %w[one two].map do |out|
        ReleaseGems.build(assets: File.join(dir, "assets"), out: File.join(dir, out), pins: pins(dir, assets))
        File.read(File.join(dir, out, "SHA256SUMS"))
      end
      assert_equal sums.first, sums.last
    end
  end

  def test_an_asset_that_is_not_the_one_pinned_builds_no_gem
    Dir.mktmpdir do |dir|
      assets = write_assets(dir)
      pinned = pins(dir, assets)
      name = "fledge-runtime-#{VERSION}-x86_64-linux-lgpl-sources.tar.gz"
      File.write(File.join(dir, "assets", name), "swapped")

      error = assert_raises(ReleaseGems::Mismatch) { ReleaseGems.build(assets: File.join(dir, "assets"), out: File.join(dir, "gems"), pins: pinned) }
      assert_includes error.message, "#{name} has SHA-256 #{Digest::SHA256.hexdigest('swapped')}"
      refute_path_exists File.join(dir, "gems")
    end
  end

  def test_a_pinned_asset_no_gem_carries_or_a_target_with_no_runtime_builds_no_gem
    Dir.mktmpdir do |dir|
      assets = write_assets(dir).reject { |name, _| name == "fledge-runtime-#{VERSION}-ios.tar.gz" }
      assets["fledge-runtime-#{VERSION}-x86_64-darwin.tar.gz"] = "a platform Fledge has no runtime for"
      File.write(File.join(dir, "assets", "fledge-runtime-#{VERSION}-x86_64-darwin.tar.gz"), "a platform Fledge has no runtime for")

      error = assert_raises(ReleaseGems::Mismatch) do
        ReleaseGems.build(assets: File.join(dir, "assets"), out: File.join(dir, "gems"), pins: pins(dir, assets))
      end
      assert_includes error.message, "fledge-runtime-#{VERSION}-x86_64-darwin.tar.gz is pinned but belongs to no runtime gem"
      assert_includes error.message, "no runtime for ios is pinned"
    end
  end

  # A person publishes Fledge on RubyGems.org from 1.0.0 (decisions,
  # 2026-11-03); a gem built before then can be pushed nowhere.
  def test_only_gems_from_one_point_oh_on_may_be_pushed_to_rubygems
    assert_equal "https://rubygems.org", ReleaseGems.push_host("1.0.0")
    assert_equal "https://rubygems.org", ReleaseGems.push_host("1.2.3")
    assert_equal "https://fledge.invalid", ReleaseGems.push_host("0.9.9")
    assert_equal "https://fledge.invalid", ReleaseGems.push_host("1.0.0.pre.1")
  end

  # Every asset of a release at VERSION, as RuntimeBuilder#assets names
  # them, in +dir+/assets: real runtime archives with an rbconfig.rb, and
  # a small SBOM; returns each name and body.
  private def write_assets(dir)
    folder = File.join(dir, "assets")
    FileUtils.mkdir_p(folder)
    sbom = JSON.generate("packages" => [
      { "licenseConcluded" => "Ruby OR BSD-2-Clause" },
      { "licenseConcluded" => "MIT AND Apache-2.0" },
      { "licenseConcluded" => "NOASSERTION" },
])
    targets = DESKTOP.map { |name| Fledge::Platform.find(name) } + PHONES.map { |name| Fledge::MobilePlatform.find(name) }
    targets.each_with_object({}) do |target, assets|
      runtime = target.is_a?(Fledge::Platform) ? FakeRuntime.write(folder, target) : FakeRuntime.write_mobile(folder, target)
      base = "fledge-runtime-#{VERSION}-#{target}"
      assets[File.basename(runtime)] = File.binread(runtime)
      assets["#{base}-NOTICES.txt"] = "notices for #{target}\n"
      assets["#{base}.spdx.json"] = sbom
      if target.is_a?(Fledge::Platform)
        assets["#{base}-dev.tar.gz"] = "companion for #{target}"
        assets["#{base}-lgpl-sources.tar.gz"] = "sources for #{target}" if target.os != "darwin"
      end
      assets.each { |name, body| File.binwrite(File.join(folder, name), body) }
    end
  end

  private def pins(dir, assets)
    path = File.join(dir, "SHA256SUMS")
    File.write(path, assets.sort.map { |name, body| "#{Digest::SHA256.hexdigest(body)}  #{name}\n" }.join)
    path
  end

  private def target_of(name)
    [*DESKTOP, *PHONES].select { |target| name.start_with?("fledge-runtime-#{VERSION}-#{target}") }.max_by(&:size)
  end

  private def gem_files(package)
    files = {}
    File.open(package.gem.path, "rb") do |io|
      Gem::Package::TarReader.new(io).each do |entry|
        next unless entry.full_name == "data.tar.gz"

        Zlib::GzipReader.wrap(entry) do |gz|
          Gem::Package::TarReader.new(gz).each { |file| files[file.full_name] = file.read.to_s.b }
        end
      end
    end
    files
  end
end
