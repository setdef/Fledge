# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/loopback_server"
require "digest"
require "stringio"

class RuntimesTest < Minitest::Test
  LINUX = Fledge::Platform.find("x86_64-linux")

  def test_file_names_carry_the_version_and_platform
    assert_equal "fledge-runtime-#{Fledge::VERSION}-x86_64-linux.tar.gz", Fledge::Runtimes.file_name(LINUX)
    assert_equal "fledge-runtime-1.2.3-arm64-darwin.tar.gz",
      Fledge::Runtimes.file_name(Fledge::Platform.find("arm64-darwin"), version: "1.2.3")
  end

  def test_the_build_only_companion_is_named_beside_the_runtime
    assert_equal "fledge-runtime-1.2.3-arm64-darwin-dev.tar.gz",
      Fledge::Runtimes.dev_file_name(Fledge::Platform.find("arm64-darwin"), version: "1.2.3")
  end

  # A gem compiled from source needs the runtime's C headers, which the
  # runtime itself prunes; they come from the same place it does.
  def test_the_build_only_companion_comes_from_where_the_runtime_does
    Dir.mktmpdir do |dir|
      dev = File.join(dir, Fledge::Runtimes.dev_file_name(LINUX))
      File.write(dev, "headers")
      runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => dir }, release_url: "http://127.0.0.1:1")

      assert_equal dev, runtimes.dev_archive(LINUX)
      error = assert_raises(Fledge::Error) { runtimes.dev_archive(Fledge::Platform.find("aarch64-linux")) }
      assert_includes error.message, "which has no fledge-runtime-#{Fledge::VERSION}-aarch64-linux-dev.tar.gz"
    end
  end

  def test_a_missing_build_only_companion_downloads_checked_against_the_gems_pins
    body = "headers"
    name = Fledge::Runtimes.dev_file_name(LINUX)
    server = LoopbackServer.new("/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      pins = write_pins(home, name => body)
      path = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"), pins:).dev_archive(LINUX)

      assert_equal File.join(home, ".cache/fledge/runtimes", name), path
      assert_equal body, File.binread(path)
    end
  ensure
    server&.stop
  end

  def test_the_runtime_directory_wins_and_is_the_only_place_looked
    Dir.mktmpdir do |dir|
      archive = FakeRuntime.write(dir, LINUX)
      runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => dir }, release_url: "http://127.0.0.1:1")

      assert_equal archive, runtimes.archive(LINUX)
      error = assert_raises(Fledge::Error) { runtimes.archive(Fledge::Platform.find("aarch64-linux")) }
      assert_equal "FLEDGE_RUNTIME_DIR is #{dir}, which has no " \
        "fledge-runtime-#{Fledge::VERSION}-aarch64-linux.tar.gz", error.message
    end
  end

  def test_the_cache_follows_xdg_cache_home_then_home
    assert_equal File.expand_path("/x/fledge/runtimes"),
      Fledge::Runtimes.new(env: { "XDG_CACHE_HOME" => "/x", "HOME" => "/h" }).cache
    assert_equal File.expand_path("/h/.cache/fledge/runtimes"),
      Fledge::Runtimes.new(env: { "XDG_CACHE_HOME" => "", "HOME" => "/h" }).cache
  end

  def test_a_cached_runtime_that_matches_its_pin_is_used_without_a_download
    Dir.mktmpdir do |home|
      cache = File.join(home, ".cache/fledge/runtimes")
      FileUtils.mkdir_p(cache)
      archive = FakeRuntime.write(cache, LINUX)
      pins = write_pins(home, File.basename(archive) => File.binread(archive))

      assert_equal archive, Fledge::Runtimes.new(env: { "HOME" => home }, release_url: "http://127.0.0.1:1", pins:).archive(LINUX)
    end
  end

  # A cache is a folder anyone with the account can write to; what it
  # holds is trusted only as far as the pin it matches.
  def test_a_cached_runtime_that_does_not_match_its_pin_is_downloaded_again
    body = "the released runtime"
    name = Fledge::Runtimes.file_name(LINUX)
    server = LoopbackServer.new("/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      cached = File.join(home, ".cache/fledge/runtimes", name)
      FileUtils.mkdir_p(File.dirname(cached))
      File.write(cached, "swapped in the cache")
      log = StringIO.new
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"), log:,
        pins: write_pins(home, name => body))

      assert_equal cached, runtimes.archive(LINUX)
      assert_equal body, File.binread(cached)
      assert_equal "#{cached} does not match the SHA-256 this Fledge pins for it; downloading it again\n" \
        "Downloading #{name} from #{server.url('/v')}\n", log.string
    end
  ensure
    server&.stop
  end

  def test_a_missing_runtime_downloads_into_the_cache_checked_against_the_gems_pins
    Dir.mktmpdir do |source|
      body = File.binread(FakeRuntime.write(source, LINUX))
      name = Fledge::Runtimes.file_name(LINUX)
      server = LoopbackServer.new("/v/#{name}" => [200, {}, body])
      log = StringIO.new
      Dir.mktmpdir do |home|
        pins = write_pins(home, "other.tar.gz" => "other", name => body)
        path = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"), log:, pins:).archive(LINUX)

        assert_equal File.join(home, ".cache/fledge/runtimes", name), path
        assert_equal body, File.binread(path)
        assert_equal "Downloading #{name} from #{server.url('/v')}\n", log.string
        assert_equal ["/v/#{name}"], server.requests
      end
    ensure
      server&.stop
    end
  end

  # The release's own SHA256SUMS would vouch for a replaced asset if it
  # were replaced too; the gem's pins were fixed when the gem was.
  def test_a_release_whose_assets_and_sums_were_both_replaced_fails
    name = Fledge::Runtimes.file_name(LINUX)
    tampered = "tampered"
    server = LoopbackServer.new("/v/SHA256SUMS" => [200, {}, "#{Digest::SHA256.hexdigest(tampered)}  #{name}\n"],
      "/v/#{name}" => [200, {}, tampered])
    Dir.mktmpdir do |home|
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"),
        pins: write_pins(home, name => "the released runtime"))

      error = assert_raises(Fledge::Error) { runtimes.archive(LINUX) }
      assert_includes error.message, "has SHA-256 #{Digest::SHA256.hexdigest(tampered)}"
      refute_path_exists File.join(home, ".cache/fledge/runtimes", name)
    end
  ensure
    server&.stop
  end

  def test_a_runtime_this_fledge_does_not_pin_fails_without_a_download
    Dir.mktmpdir do |home|
      [write_pins(home, "other.tar.gz" => "other"), File.join(home, "absent")].each do |pins|
        runtimes = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: "http://127.0.0.1:1", pins:)

        error = assert_raises(Fledge::Error) { runtimes.archive(LINUX) }
        assert_equal "Fledge #{Fledge::VERSION} pins no SHA-256 for #{Fledge::Runtimes.file_name(LINUX)}, " \
          "so it is not a released Fledge and has no runtimes to download. Install Fledge from a release " \
          "tag, or set FLEDGE_RUNTIME_DIR to a folder of runtimes you built (rake runtime).", error.message
      end
    end
  end

  # The pins the gem ships are SHA256SUMS lines, as sha256sum -c reads
  # them, for one version's release assets.
  def test_the_shipped_pins_are_one_releases_sha256sums
    lines = File.readlines(Fledge::Runtimes::PINS, chomp: true)
    versions = lines.map do |line|
      assert_match(/\A\h{64}  fledge-runtime-\S+\z/, line)
      line[/fledge-runtime-(\d+\.\d+\.\d+(?:\.pre\.\d+)?)-/, 1]
    end

    refute_empty lines
    assert_equal 1, versions.uniq.size, "the pins are for one version"
    names = lines.map { |line| line.split("  ", 2).last }
    assert_equal names.sort, names
  end

  private def write_pins(dir, bodies)
    path = File.join(dir, "SHA256SUMS")
    File.write(path, bodies.map { |name, body| "#{Digest::SHA256.hexdigest(body)}  #{name}\n" }.join)
    path
  end
end
