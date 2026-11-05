# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "digest"
require "stringio"
require_relative "support/loopback_server"
require_relative "../tasks/download_cache"

# A pin's mirrors, tried in order after its URL, each download checked
# against the one SHA-256 the pin names.
class DownloadCacheTest < Minitest::Test
  BODY = ("musl source " * 1_000).freeze
  SHA = Digest::SHA256.hexdigest(BODY)

  def setup
    @server = LoopbackServer.new({
      "/primary/musl-1.2.5.tar.gz" => [503, {}, "down"],
      "/other/musl-1.2.5.tar.gz" => [200, {}, "#{BODY}, changed"],
      "/mirror/musl_1.2.5.orig.tar.gz" => [200, {}, BODY],
    })
    @dead = "http://127.0.0.1:1/musl-1.2.5.tar.gz"
  end

  def teardown
    @server.stop
  end

  def cache(dir, **)
    @waits = []
    DownloadCache.new(dir, sleeper: @waits.method(:push), **)
  end

  def quietly(&)
    $stdout = StringIO.new
    yield
  ensure
    $stdout = STDOUT
  end

  def test_a_mirror_serves_the_file_when_the_url_cannot_and_keeps_the_urls_file_name
    Dir.mktmpdir do |dir|
      path = quietly { cache(dir).fetch(@dead, SHA, mirrors: [@server.url("/mirror/musl_1.2.5.orig.tar.gz")]) }

      assert_equal File.join(dir, "musl-1.2.5.tar.gz"), path
      assert_equal BODY, File.read(path)
      assert_equal ["musl-1.2.5.tar.gz"], Dir.children(dir)
    end
  end

  def test_a_mirror_serving_other_bytes_is_rejected_and_the_next_one_tried
    mirrors = [@server.url("/other/musl-1.2.5.tar.gz"), @server.url("/mirror/musl_1.2.5.orig.tar.gz")]
    Dir.mktmpdir do |dir|
      path = quietly { cache(dir).fetch(@server.url("/primary/musl-1.2.5.tar.gz"), SHA, mirrors:) }

      assert_equal BODY, File.read(path)
      assert_equal [*%w[/primary/musl-1.2.5.tar.gz] * 5, "/other/musl-1.2.5.tar.gz", "/mirror/musl_1.2.5.orig.tar.gz"], @server.requests
    end
  end

  def test_the_url_comes_first_and_its_mirrors_are_not_asked_when_it_answers
    mirror = LoopbackServer.new({ "/musl-1.2.5.tar.gz" => [200, {}, BODY] })
    Dir.mktmpdir do |dir|
      quietly { cache(dir).fetch(mirror.url("/musl-1.2.5.tar.gz"), SHA, mirrors: [@server.url("/mirror/musl_1.2.5.orig.tar.gz")]) }

      assert_empty @server.requests
    end
  ensure
    mirror&.stop
  end

  def test_when_every_url_fails_the_error_names_each_one_and_why
    primary = @server.url("/primary/musl-1.2.5.tar.gz")
    other = @server.url("/other/musl-1.2.5.tar.gz")
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { quietly { cache(dir).fetch(primary, SHA, mirrors: [other, @dead]) } }

      lines = error.message.lines(chomp: true)
      assert_equal "could not download musl-1.2.5.tar.gz from any of its 3 URLs:", lines[0]
      assert_equal "  could not download #{primary}: 503 X", lines[1]
      assert_match(/\A  #{Regexp.escape(other)} has SHA-256 \h{64}, but #{SHA} was expected\./, lines[2])
      assert_match(/\A  could not download #{Regexp.escape(@dead)}: /, lines[3])
      assert_equal 4, lines.size
      assert_empty Dir.children(dir)
    end
  end

  def test_a_pin_without_mirrors_fails_with_its_one_error
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { quietly { cache(dir).fetch(@server.url("/primary/musl-1.2.5.tar.gz"), SHA) } }

      assert_equal "could not download #{@server.url('/primary/musl-1.2.5.tar.gz')}: 503 X", error.message
    end
  end

  def test_a_cached_file_is_used_without_downloading
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "musl-1.2.5.tar.gz"), BODY)

      assert_equal File.join(dir, "musl-1.2.5.tar.gz"), cache(dir).fetch(@dead, SHA, mirrors: [@dead])
    end
  end

  def test_a_server_that_answers_504_a_few_times_is_asked_again_with_growing_waits
    answers = [[504, {}, "Gateway Time-out"], [504, {}, ""], [200, {}, BODY]]
    server = LoopbackServer.new({ "/musl.tar.gz" => -> { answers.shift } })
    Dir.mktmpdir do |dir|
      path = quietly { cache(dir).fetch(server.url("/musl.tar.gz"), SHA) }

      assert_equal BODY, File.read(path)
      assert_equal %w[/musl.tar.gz] * 3, server.requests
      assert_equal [5, 10], @waits
    end
  ensure
    server&.stop
  end

  def test_the_retries_are_bounded_and_the_waits_stop_growing_at_a_minute
    server = LoopbackServer.new({ "/musl.tar.gz" => [503, {}, "down"] })
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { quietly { cache(dir, tries: 8).fetch(server.url("/musl.tar.gz"), SHA) } }

      assert_equal "could not download #{server.url('/musl.tar.gz')}: 503 X", error.message
      assert_equal 8, server.requests.size
      assert_equal [5, 10, 20, 40, 60, 60, 60], @waits
    end
  ensure
    server&.stop
  end

  def test_429_and_408_are_retried
    [429, 408].each do |status|
      answers = [[status, {}, ""], [200, {}, BODY]]
      server = LoopbackServer.new({ "/f" => -> { answers.shift } })
      Dir.mktmpdir { |dir| quietly { cache(dir).fetch(server.url("/f"), SHA) } }

      assert_equal 2, server.requests.size, "status #{status}"
      server.stop
    end
  end

  def test_a_connection_that_fails_is_retried
    Dir.mktmpdir do |dir|
      assert_raises(Fledge::Error) { quietly { cache(dir, tries: 3).fetch(@dead, SHA) } }

      assert_equal [5, 10], @waits
    end
  end

  def test_a_wrong_body_is_not_retried
    server = LoopbackServer.new({ "/f" => [200, {}, "#{BODY}, changed"] })
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { quietly { cache(dir).fetch(server.url("/f"), SHA) } }

      assert_match(/has SHA-256 \h{64}, but #{SHA} was expected/, error.message)
      assert_equal ["/f"], server.requests
      assert_empty @waits
      assert_empty Dir.children(dir)
    end
  ensure
    server&.stop
  end

  def test_a_4xx_is_not_retried
    server = LoopbackServer.new({ "/gone" => [404, {}, ""], "/denied" => [403, {}, ""], "/bad" => [400, {}, ""] })
    Dir.mktmpdir do |dir|
      %w[/gone /denied /bad].each do |path|
        assert_raises(Fledge::Error) { quietly { cache(dir).fetch(server.url(path), SHA) } }
      end

      assert_equal %w[/gone /denied /bad], server.requests
      assert_empty @waits
    end
  ensure
    server&.stop
  end
end
