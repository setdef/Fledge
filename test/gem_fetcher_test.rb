# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/gems"
require_relative "support/loopback_server"
require "stringio"

class GemFetcherTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @built = FakeGem.build(@dir, "foo")
    @server = LoopbackServer.new("/gems/foo-1.0.0.gem" => [200, {}, File.binread(@built.path)])
    @gem = Fledge::LockedGem.new(name: "foo", version: "1.0.0", platform: "ruby", remote: @server.url("/"), sha256: @built.sha256)
    @project = File.join(@dir, "project")
    @log = StringIO.new
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@dir)
  end

  def fetcher(gem_path: [])
    Fledge::GemFetcher.new(cache: File.join(@dir, "cache"), project: @project, gem_path:, log: @log)
  end

  def place(folder)
    FileUtils.mkdir_p(folder)
    FileUtils.cp(@built.path, folder)
    File.join(folder, @built.file_name)
  end

  def test_downloads_into_its_cache_once
    path = fetcher.fetch(@gem)

    assert_equal File.join(@dir, "cache", "foo-1.0.0.gem"), path
    assert_equal File.binread(@built.path), File.binread(path)
    assert_equal path, fetcher.fetch(@gem)
    assert_equal ["/gems/foo-1.0.0.gem"], @server.requests
    assert_equal "Downloading foo-1.0.0.gem from #{@server.url('/')}\n", @log.string
  end

  def test_takes_the_projects_vendor_cache_then_rubygems_caches
    vendored = place(File.join(@project, "vendor", "cache"))
    assert_equal vendored, fetcher.fetch(@gem)

    File.delete(vendored)
    installed = place(File.join(@dir, "gem_home", "cache"))
    assert_equal installed, fetcher(gem_path: [File.join(@dir, "gem_home")]).fetch(@gem)
    assert_empty @server.requests
  end

  def test_a_copy_whose_sha256_differs_is_passed_over
    File.write(File.join(FileUtils.mkdir_p(File.join(@project, "vendor", "cache")).first, "foo-1.0.0.gem"), "tampered")

    assert_equal File.join(@dir, "cache", "foo-1.0.0.gem"), fetcher.fetch(@gem)
    assert_equal ["/gems/foo-1.0.0.gem"], @server.requests
  end

  def test_a_download_whose_sha256_differs_is_refused
    gem = @gem.with(sha256: "0" * 64)

    error = assert_raises(Fledge::Error) { fetcher.fetch(gem) }
    assert_includes error.message, "SHA-256"
    refute_path_exists File.join(@dir, "cache", "foo-1.0.0.gem")
  end
end
