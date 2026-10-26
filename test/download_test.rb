# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "digest"
require_relative "support/loopback_server"

class DownloadTest < Minitest::Test
  BODY = ("runtime bytes " * 10_000).freeze
  SHA = Digest::SHA256.hexdigest(BODY)

  def setup
    @server = LoopbackServer.new(
      "/file" => [200, {}, BODY],
      "/hop" => [302, { "Location" => "/file" }, ""],
      "/loop" => [302, { "Location" => "/loop" }, ""],
      "/downgrade" => [302, { "Location" => "http://127.0.0.1:1/file" }, ""]
    )
  end

  def teardown
    @server.stop
  end

  def test_save_writes_a_file_whose_sha256_matches
    Dir.mktmpdir do |dir|
      to = File.join(dir, "deep/runtime.tar.gz")

      assert_equal to, Fledge::Download.save(@server.url("/file"), to:, sha256: SHA)
      assert_equal BODY, File.read(to)
      assert_equal ["runtime.tar.gz"], Dir.children(File.dirname(to))
    end
  end

  def test_save_accepts_an_uppercase_pin
    Dir.mktmpdir do |dir|
      Fledge::Download.save(@server.url("/file"), to: File.join(dir, "f"), sha256: SHA.upcase)

      assert_path_exists File.join(dir, "f")
    end
  end

  def test_save_fails_loudly_and_keeps_nothing_on_a_sha256_mismatch
    Dir.mktmpdir do |dir|
      to = File.join(dir, "runtime.tar.gz")
      wrong = "0" * 64

      error = assert_raises(Fledge::Error) { Fledge::Download.save(@server.url("/file"), to:, sha256: wrong) }

      assert_equal "#{@server.url('/file')} has SHA-256 #{SHA}, but #{wrong} was expected. " \
        "The file changed since it was pinned, or the download was damaged; nothing was saved.", error.message
      assert_empty Dir.children(dir)
    end
  end

  def test_redirects_are_followed
    assert_equal BODY, Fledge::Download.read(@server.url("/hop"))
    assert_equal ["/hop", "/file"], @server.requests
  end

  def test_redirect_loops_end
    error = assert_raises(Fledge::Error) { Fledge::Download.read(@server.url("/loop")) }

    assert_match(/redirected more than 5 times/, error.message)
    assert_equal 6, @server.requests.size
  end

  def test_a_missing_file_is_an_error
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) { Fledge::Download.save(@server.url("/nope"), to: File.join(dir, "f"), sha256: SHA) }

      assert_equal "could not download #{@server.url('/nope')}: 404 X", error.message
      assert_empty Dir.children(dir)
    end
  end

  def test_an_unreachable_server_is_an_error
    error = assert_raises(Fledge::Error) { Fledge::Download.read("http://127.0.0.1:1/file") }

    assert_match(%r{\Acould not download http://127.0.0.1:1/file: }, error.message)
  end

  def test_only_http_and_https_are_downloaded
    error = assert_raises(Fledge::Error) { Fledge::Download.read("file:///etc/passwd") }

    assert_equal "file:///etc/passwd is not an http or https URL", error.message
  end
end
