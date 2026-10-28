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

  def test_makensis_is_named_for_the_computer_that_runs_it
    assert_equal "fledge-makensis-1.2.3-aarch64-linux.tar.gz",
      Fledge::Runtimes.makensis_file_name(Fledge::Platform.find("aarch64-linux"), version: "1.2.3")
  end

  # makensis comes from where the runtimes do, and runs from a folder it
  # is unpacked into, once, beside the cache's runtimes.
  def test_makensis_is_unpacked_once_from_where_the_runtimes_come_from
    Dir.mktmpdir do |dir|
      windows = Fledge::Platform.find("x64-mingw-ucrt")
      top = "fledge-makensis-#{Fledge::VERSION}-x64-mingw-ucrt"
      Fledge::TarGz.write(File.join(dir, "#{top}.tar.gz")) do |tar|
        tar.add(Fledge::Entry.directory(top))
        tar.add(Fledge::Entry.file("#{top}/makensis.exe", "MZ", mode: 0o755))
        tar.add(Fledge::Entry.file("#{top}/zlib1.dll", "MZ"))
      end
      runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => dir, "XDG_CACHE_HOME" => File.join(dir, "cache") })

      program = runtimes.makensis(windows)
      assert_equal File.join(dir, "cache/fledge/runtimes", top, "makensis.exe"), program
      assert_equal "MZ", File.read(program)
      assert_path_exists File.join(File.dirname(program), "zlib1.dll")
      File.write(program, "kept")
      assert_equal "kept", File.read(runtimes.makensis(windows))
      error = assert_raises(Fledge::Error) { runtimes.makensis(LINUX) }
      assert_includes error.message, "which has no fledge-makensis-#{Fledge::VERSION}-x86_64-linux.tar.gz"
    end
  end

  def test_an_archive_that_is_not_makensis_is_refused
    Dir.mktmpdir do |dir|
      Fledge::TarGz.write(File.join(dir, Fledge::Runtimes.makensis_file_name(LINUX))) { |tar| tar.add(Fledge::Entry.file("other/makensis", "x")) }
      runtimes = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => dir, "XDG_CACHE_HOME" => File.join(dir, "cache") })

      assert_match(/is not Fledge's makensis/, assert_raises(Fledge::Error) { runtimes.makensis(LINUX) }.message)
    end
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

  def test_a_missing_build_only_companion_downloads_checked_against_the_release_sums
    body = "headers"
    name = Fledge::Runtimes.dev_file_name(LINUX)
    server = LoopbackServer.new("/v/SHA256SUMS" => [200, {}, "#{Digest::SHA256.hexdigest(body)}  #{name}\n"], "/v/#{name}" => [200, {}, body])
    Dir.mktmpdir do |home|
      path = Fledge::Runtimes.new(env: { "HOME" => home }, release_url: server.url("/v")).dev_archive(LINUX)

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
