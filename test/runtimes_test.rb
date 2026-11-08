# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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

  # fledge build --from downloads nothing: it takes a runtime only when
  # this computer has it, from FLEDGE_RUNTIME_DIR, or from the cache when
  # it matches its pin (ADR 032).
  def test_a_runtime_at_hand_is_one_this_computer_has_and_nothing_is_downloaded
    Dir.mktmpdir do |home|
      archive = FakeRuntime.write(home, LINUX)
      assert_equal archive, Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => home }).at_hand(LINUX)
      assert_nil Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => home }).at_hand(Fledge::Platform.find("aarch64-linux"))

      cache = File.join(home, ".cache/fledge/runtimes")
      FileUtils.mkdir_p(cache)
      cached = FakeRuntime.write(cache, LINUX)
      pins = write_pins(home, File.basename(cached) => File.binread(cached))
      assert_equal cached, Fledge::Runtimes.new(env: { "HOME" => home }, release_url: "http://127.0.0.1:1", pins:).at_hand(LINUX)

      File.write(cached, "swapped in the cache")
      assert_nil Fledge::Runtimes.new(env: { "HOME" => home }, release_url: "http://127.0.0.1:1", pins:).at_hand(LINUX)
      assert_nil Fledge::Runtimes.new(env: { "HOME" => home }, pins: File.join(home, "none")).at_hand(LINUX)
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

  # FLEDGE_RUNTIME_MIRROR replaces the releases' download base, as
  # UV_PYTHON_INSTALL_MIRROR replaces python-build-standalone's: the same
  # tag folder and file names, checked against the same pins.
  def test_a_mirror_replaces_the_release_and_its_downloads_are_checked_against_the_pins
    body = "the released runtime"
    name = Fledge::Runtimes.file_name(LINUX)
    mirror = LoopbackServer.new("/fledge/v#{Fledge::VERSION}/#{name}" => [200, {}, body])
    release = LoopbackServer.new("/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      log = StringIO.new
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home, "FLEDGE_RUNTIME_MIRROR" => "#{mirror.url('/fledge')}/" },
        release_url: release.url("/v"), log:, pins: write_pins(home, name => body))

      path = runtimes.archive(LINUX)
      assert_equal File.join(home, ".cache/fledge/runtimes", name), path
      assert_equal body, File.binread(path)
      assert_equal path, runtimes.archive(LINUX)
      assert_equal "Downloading #{name} from #{mirror.url('/fledge')}/v#{Fledge::VERSION}\n", log.string
      assert_equal ["/fledge/v#{Fledge::VERSION}/#{name}"], mirror.requests
      assert_empty release.requests
    end
  ensure
    mirror&.stop
    release&.stop
  end

  # The pins make any host safe to download from; they also make a host
  # that serves other bytes plain to see.
  def test_a_mirror_that_serves_other_bytes_is_refused_naming_it_and_both_sha256s
    name = Fledge::Runtimes.file_name(LINUX)
    tampered = "tampered"
    mirror = LoopbackServer.new("/v#{Fledge::VERSION}/#{name}" => [200, {}, tampered])
    Dir.mktmpdir do |home|
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home, "FLEDGE_RUNTIME_MIRROR" => mirror.url("") },
        release_url: "http://127.0.0.1:1", pins: write_pins(home, name => "the released runtime"))

      error = assert_raises(Fledge::Error) { runtimes.archive(LINUX) }
      assert_equal "FLEDGE_RUNTIME_MIRROR is #{mirror.url('')}, whose #{name} has SHA-256 " \
        "#{Digest::SHA256.hexdigest(tampered)}, but Fledge #{Fledge::VERSION} pins " \
        "#{Digest::SHA256.hexdigest('the released runtime')} for it. The mirror does not hold the file this " \
        "Fledge released; nothing was saved.", error.message
      refute_path_exists File.join(home, ".cache/fledge/runtimes", name)
    end
  ensure
    mirror&.stop
  end

  # A mirror is chosen on purpose, often because the release's host is
  # not to be reached; a file it lacks fails rather than quietly coming
  # from the release, as uv and rustup do with theirs.
  def test_a_mirror_without_the_file_fails_and_does_not_fall_back_to_the_release
    body = "the released runtime"
    name = Fledge::Runtimes.dev_file_name(LINUX)
    mirror = LoopbackServer.new
    release = LoopbackServer.new("/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home, "FLEDGE_RUNTIME_MIRROR" => mirror.url("/m") },
        release_url: release.url("/v"), pins: write_pins(home, name => body))

      error = assert_raises(Fledge::Error) { runtimes.dev_archive(LINUX) }
      assert_equal "FLEDGE_RUNTIME_MIRROR is #{mirror.url('/m')}: could not download " \
        "#{mirror.url("/m/v#{Fledge::VERSION}/#{name}")}: 404 X", error.message
      assert_empty release.requests
    end
  ensure
    mirror&.stop
    release&.stop
  end

  # GitHub's release downloads answer 5xx now and then and pass a moment
  # later (ADR 014, section 6).
  def test_a_release_that_fails_for_a_moment_is_asked_again_and_the_log_says_so
    body = "the released runtime"
    name = Fledge::Runtimes.file_name(LINUX)
    answers = [[502, {}, "Bad Gateway"], [200, {}, body]]
    server = LoopbackServer.new("/v/#{name}" => -> { answers.shift })
    Dir.mktmpdir do |home|
      log = StringIO.new
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"), log:,
        pins: write_pins(home, name => body), waits: [0, 0])

      assert_equal body, File.binread(runtimes.archive(LINUX))
      assert_equal "Downloading #{name} from #{server.url('/v')}\n" \
        "could not download #{server.url("/v/#{name}")}: 502 X; trying again in 0 seconds (2 of 3)\n", log.string
      assert_equal ["/v/#{name}"] * 2, server.requests
    end
  ensure
    server&.stop
  end

  # A mirror is asked again as the release is, and still not passed over
  # when it keeps failing (ADR 031, section 3).
  def test_a_mirror_that_keeps_failing_is_asked_again_and_then_fails_without_the_release
    body = "the released runtime"
    name = Fledge::Runtimes.file_name(LINUX)
    mirror = LoopbackServer.new("/v#{Fledge::VERSION}/#{name}" => [503, {}, "down"])
    release = LoopbackServer.new("/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home, "FLEDGE_RUNTIME_MIRROR" => mirror.url("") },
        release_url: release.url("/v"), pins: write_pins(home, name => body), waits: [0, 0])

      error = assert_raises(Fledge::Error) { runtimes.archive(LINUX) }
      assert_equal "FLEDGE_RUNTIME_MIRROR is #{mirror.url('')}: could not download " \
        "#{mirror.url("/v#{Fledge::VERSION}/#{name}")}: 503 X", error.message
      assert_equal 3, mirror.requests.size
      assert_empty release.requests
    end
  ensure
    mirror&.stop
    release&.stop
  end

  def test_the_runtime_directory_wins_over_a_mirror
    Dir.mktmpdir do |dir|
      archive = FakeRuntime.write(dir, LINUX)
      runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => dir, "FLEDGE_RUNTIME_MIRROR" => "http://127.0.0.1:1" })

      assert_equal archive, runtimes.archive(LINUX)
    end
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
