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

  def test_a_cached_runtime_is_used_without_a_download
    Dir.mktmpdir do |home|
      cache = File.join(home, ".cache/fledge/runtimes")
      FileUtils.mkdir_p(cache)
      archive = FakeRuntime.write(cache, LINUX)

      assert_equal archive, Fledge::Runtimes.new(env: { "HOME" => home }, release_url: "http://127.0.0.1:1").archive(LINUX)
    end
  end

  def test_a_missing_runtime_downloads_into_the_cache_checked_against_the_release_sums
    Dir.mktmpdir do |source|
      body = File.binread(FakeRuntime.write(source, LINUX))
      name = Fledge::Runtimes.file_name(LINUX)
      sums = "#{'1' * 64}  other.tar.gz\n#{Digest::SHA256.hexdigest(body)}  #{name}\n"
      server = LoopbackServer.new("/v/SHA256SUMS" => [200, {}, sums], "/v/#{name}" => [200, {}, body])
      log = StringIO.new
      Dir.mktmpdir do |home|
        path = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"), log:).archive(LINUX)

        assert_equal File.join(home, ".cache/fledge/runtimes", name), path
        assert_equal body, File.binread(path)
        assert_equal "Downloading #{name} from #{server.url('/v')}\n", log.string
      end
    ensure
      server&.stop
    end
  end

  def test_a_download_that_does_not_match_the_release_sums_fails
    name = Fledge::Runtimes.file_name(LINUX)
    server = LoopbackServer.new("/v/SHA256SUMS" => [200, {}, "#{'0' * 64}  #{name}\n"], "/v/#{name}" => [200, {}, "tampered"])
    Dir.mktmpdir do |home|
      runtimes = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v"))

      assert_raises(Fledge::Error) { runtimes.archive(LINUX) }
      refute_path_exists File.join(home, ".cache/fledge/runtimes", name)
    end
  ensure
    server&.stop
  end

  def test_a_release_whose_sums_omit_the_runtime_fails
    server = LoopbackServer.new("/v/SHA256SUMS" => [200, {}, "#{'0' * 64}  other\n"])
    Dir.mktmpdir do |home|
      error = assert_raises(Fledge::Error) do
        Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v")).archive(LINUX)
      end

      assert_equal "#{server.url('/v/SHA256SUMS')} lists no #{Fledge::Runtimes.file_name(LINUX)}", error.message
    end
  ensure
    server&.stop
  end
end
