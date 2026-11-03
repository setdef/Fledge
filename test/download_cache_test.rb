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

  def quietly(&)
    $stdout = StringIO.new
    yield
  ensure
    $stdout = STDOUT
  end

  def test_a_mirror_serves_the_file_when_the_url_cannot_and_keeps_the_urls_file_name
    Dir.mktmpdir do |dir|
      path = quietly { DownloadCache.new(dir).fetch(@dead, SHA, mirrors: [@server.url("/mirror/musl_1.2.5.orig.tar.gz")]) }

      assert_equal File.join(dir, "musl-1.2.5.tar.gz"), path
      assert_equal BODY, File.read(path)
      assert_equal ["musl-1.2.5.tar.gz"], Dir.children(dir)
    end
  end

  def test_a_mirror_serving_other_bytes_is_rejected_and_the_next_one_tried
    mirrors = [@server.url("/other/musl-1.2.5.tar.gz"), @server.url("/mirror/musl_1.2.5.orig.tar.gz")]
    Dir.mktmpdir do |dir|
      path = quietly { DownloadCache.new(dir).fetch(@server.url("/primary/musl-1.2.5.tar.gz"), SHA, mirrors:) }

      assert_equal BODY, File.read(path)
      assert_equal %w[/primary/musl-1.2.5.tar.gz /other/musl-1.2.5.tar.gz /mirror/musl_1.2.5.orig.tar.gz], @server.requests
    end
  end

  def test_the_url_comes_first_and_its_mirrors_are_not_asked_when_it_answers
    mirror = LoopbackServer.new({ "/musl-1.2.5.tar.gz" => [200, {}, BODY] })
    Dir.mktmpdir do |dir|
      quietly { DownloadCache.new(dir).fetch(mirror.url("/musl-1.2.5.tar.gz"), SHA, mirrors: [@server.url("/mirror/musl_1.2.5.orig.tar.gz")]) }

      assert_empty @server.requests
    end
  ensure
    mirror&.stop
  end

  def test_when_every_url_fails_the_error_names_each_one_and_why
    primary = @server.url("/primary/musl-1.2.5.tar.gz")
    other = @server.url("/other/musl-1.2.5.tar.gz")
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { quietly { DownloadCache.new(dir).fetch(primary, SHA, mirrors: [other, @dead]) } }

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
      error = assert_raises(Fledge::Error) { quietly { DownloadCache.new(dir).fetch(@server.url("/primary/musl-1.2.5.tar.gz"), SHA) } }

      assert_equal "could not download #{@server.url('/primary/musl-1.2.5.tar.gz')}: 503 X", error.message
    end
  end

  def test_a_cached_file_is_used_without_downloading
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "musl-1.2.5.tar.gz"), BODY)

      assert_equal File.join(dir, "musl-1.2.5.tar.gz"), DownloadCache.new(dir).fetch(@dead, SHA, mirrors: [@dead])
    end
  end
end
