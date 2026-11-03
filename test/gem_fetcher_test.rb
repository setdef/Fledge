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
    @server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [200, {}, File.binread(@built.path)] })
    @gem = Fledge::LockedGem.new(name: "foo", version: "1.0.0", platform: "ruby", remote: @server.url("/"), sha256: @built.sha256, credentials: nil)
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

  def test_a_server_that_wants_a_login_gets_the_one_the_gem_carries_and_the_log_never_shows_it
    server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [200, {}, File.binread(@built.path)] }, credentials: "me:secret")
    gem = @gem.with(remote: server.url("/"), credentials: "me:secret")

    path = fetcher.fetch(gem)

    assert_equal File.binread(@built.path), File.binread(path)
    assert_equal "Downloading foo-1.0.0.gem from #{server.url('/')}\n", @log.string
    refute_includes @log.string, "secret"
  ensure
    server&.stop
  end

  def test_a_server_that_wants_a_login_nobody_set_says_how_to_set_it_as_bundler_reads_it
    server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [200, {}, File.binread(@built.path)] }, credentials: "me:secret")

    error = assert_raises(Fledge::Error) { fetcher.fetch(@gem.with(remote: server.url("/"))) }

    assert_equal "foo 1.0.0 comes from #{server.url('/')}, which answered 401 for it, and there is no login for it. Set one as " \
      "Bundler reads it: bundle config set --local 127.0.0.1 USER:PASSWORD (or the environment variable BUNDLE_127__0__0__1), " \
      "then build again.", error.message
  ensure
    server&.stop
  end

  def test_a_login_the_server_refuses_is_named_without_its_password
    server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [200, {}, File.binread(@built.path)] }, credentials: "me:secret")

    error = assert_raises(Fledge::Error) { fetcher.fetch(@gem.with(remote: server.url("/"), credentials: "me:wrong")) }

    assert_includes error.message, "answered 401 for it, and Bundler's login for 127.0.0.1 was refused"
    refute_includes error.message, "wrong"
  ensure
    server&.stop
  end

  def test_a_server_without_the_file_says_so_and_where_else_the_file_can_come_from
    error = assert_raises(Fledge::Error) { fetcher.fetch(@gem.with(version: "2.0.0")) }

    assert_equal "foo 2.0.0 comes from #{@server.url('/')}, which has no foo-2.0.0.gem (it answered 404). Put that file in the " \
      "project's vendor/cache, as bundle cache --all-platforms does, or point the Gemfile at the source that has it and run " \
      "bundle lock, then build again.", error.message
  end

  # A server other than RubyGems.org that forbids a download nobody logged
  # in for is taken at its word, as Bundler takes a 403
  # (Bundler::Fetcher::AuthenticationForbiddenError).
  def test_a_private_server_that_forbids_a_download_without_a_login_says_how_to_set_one
    server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [403, {}, "forbidden"] })

    error = assert_raises(Fledge::Error) { fetcher.fetch(@gem.with(remote: server.url("/"))) }

    assert_includes error.message, "which answered 403 for it, and there is no login for it. Set one as Bundler reads it"
  ensure
    server&.stop
  end

  def test_a_login_a_server_forbids_is_named_as_refused
    server = LoopbackServer.new({ "/gems/foo-1.0.0.gem" => [403, {}, "forbidden"] })

    error = assert_raises(Fledge::Error) { fetcher.fetch(@gem.with(remote: server.url("/"), credentials: "me:wrong")) }

    assert_includes error.message, "answered 403 for it, and Bundler's login for 127.0.0.1 was refused"
  ensure
    server&.stop
  end

  # RubyGems.org serves gem files from a bucket that answers 403, not 404,
  # for a file it does not have, and needs no login for any file it has.
  # The loopback server stands in for it as an HTTP proxy, which Net::HTTP
  # finds in http_proxy, so the request still goes to the host
  # rubygems.org.
  def test_rubygems_org_forbidding_a_file_without_a_login_means_it_does_not_have_it
    proxy = LoopbackServer.new({
      "http://rubygems.org/gems/foo-1.0.0-arm64-darwin.gem" => [403, {}, "AccessDenied"],
      "http://rubygems.org/gems/foo-1.0.0.gem" => [401, {}, "login"],
    })
    gem = @gem.with(remote: "http://rubygems.org/", platform: "arm64-darwin")
    saved = %w[http_proxy HTTP_PROXY no_proxy NO_PROXY].to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV.update(saved.transform_values { nil }.merge("http_proxy" => proxy.url("")))

    error = assert_raises(Fledge::Error) { fetcher.fetch(gem) }

    assert_equal ["http://rubygems.org/gems/foo-1.0.0-arm64-darwin.gem"], proxy.requests
    assert_equal "foo 1.0.0 (arm64-darwin) comes from http://rubygems.org/, which has no foo-1.0.0-arm64-darwin.gem " \
      "(it answered 403). Put that file in the project's vendor/cache, as bundle cache --all-platforms does, or point the " \
      "Gemfile at the source that has it and run bundle lock, then build again.", error.message
    error = assert_raises(Fledge::Error) { fetcher.fetch(gem.with(credentials: "me:token")) }
    assert_includes error.message, "answered 403 for it, and Bundler's login for rubygems.org was refused"
    error = assert_raises(Fledge::Error) { fetcher.fetch(gem.with(platform: "ruby")) }
    assert_includes error.message, "answered 401 for it, and there is no login for it"
  ensure
    ENV.update(saved) if saved
    proxy&.stop
  end
end
