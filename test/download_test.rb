# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "digest"
require "stringio"
require_relative "support/loopback_server"

class DownloadTest < Minitest::Test
  BODY = ("runtime bytes " * 10_000).freeze
  SHA = Digest::SHA256.hexdigest(BODY)

  def setup
    @server = LoopbackServer.new({
      "/file" => [200, {}, BODY],
      "/hop" => [302, { "Location" => "/file" }, ""],
      "/loop" => [302, { "Location" => "/loop" }, ""],
      "/downgrade" => [302, { "Location" => "http://127.0.0.1:1/file" }, ""],
    })
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

      error = assert_raises(Fledge::Download::Mismatch) { Fledge::Download.save(@server.url("/file"), to:, sha256: wrong) }

      assert_equal "#{@server.url('/file')} has SHA-256 #{SHA}, but #{wrong} was expected. " \
        "The file changed since it was pinned, or the download was damaged; nothing was saved.", error.message
      assert_equal [SHA, wrong], [error.actual, error.expected]
      assert_kind_of Fledge::Error, error
      assert_empty Dir.children(dir)
    end
  end

  def test_save_logs_in_with_the_credentials_it_is_given_and_a_server_that_wants_them_refuses_without
    server = LoopbackServer.new({ "/file" => [200, {}, BODY] }, credentials: "me:p@ss:word")
    Dir.mktmpdir do |dir|
      to = File.join(dir, "f")

      Fledge::Download.save(server.url("/file"), to:, sha256: SHA, credentials: "me:p%40ss:word")

      assert_equal BODY, File.read(to)
      error = assert_raises(Fledge::Download::Refused) { Fledge::Download.save(server.url("/file"), to: File.join(dir, "g"), sha256: SHA) }
      assert_equal 401, error.status
      assert_equal "could not download #{server.url('/file')}: 401 X", error.message
      assert_equal [nil, "Basic #{['me:p@ss:word'].pack('m0')}"], server.authorizations.reverse
    end
  ensure
    server&.stop
  end

  def test_save_raises_missing_with_the_status_of_a_server_that_has_no_such_file
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Download::Missing) { Fledge::Download.save(@server.url("/nothing"), to: File.join(dir, "f"), sha256: SHA) }

      assert_equal 404, error.status
      assert_equal "could not download #{@server.url('/nothing')}: 404 X", error.message
      assert_empty Dir.children(dir)
    end
  end

  def test_credentials_go_only_to_the_host_that_asked_for_them
    other = LoopbackServer.new({ "/file" => [200, {}, BODY] })
    server = LoopbackServer.new({ "/away" => [302, { "Location" => "http://localhost:#{other.url('/').split(':').last.delete('/')}/file" }, ""] })
    Dir.mktmpdir do |dir|
      Fledge::Download.save(server.url("/away"), to: File.join(dir, "f"), sha256: SHA, credentials: "me:secret")
    end

    assert_equal ["Basic #{['me:secret'].pack('m0')}"], server.authorizations
    assert_equal [nil], other.authorizations
  ensure
    server&.stop
    other&.stop
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

  # A host that fails for a moment (doc/contributors/design/runtimes.md,
  # "Download retries"): 408, 429, a 5xx, or a connection that breaks
  # off, is asked again after each of the waits, and what it then sends
  # is still checked against the pin.
  def test_a_server_that_fails_for_a_moment_is_asked_again_and_the_file_checked
    answers = [[503, {}, "down"], [429, {}, ""], [200, {}, BODY]]
    server = LoopbackServer.new({ "/file" => -> { answers.shift } })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      to = File.join(dir, "runtime.tar.gz")

      assert_equal to, Fledge::Download.save(server.url("/file"), to:, sha256: SHA, waits: [0, 0, 0], log:)
      assert_equal BODY, File.read(to)
      assert_equal %w[/file] * 3, server.requests
      assert_equal "could not download #{server.url('/file')}: 503 X; trying again in 0 seconds (2 of 4)\n" \
        "could not download #{server.url('/file')}: 429 X; trying again in 0 seconds (3 of 4)\n", log.string
      assert_equal ["runtime.tar.gz"], Dir.children(dir)
    end
  ensure
    server&.stop
  end

  # A body cut short, which Net::HTTP reads as the end of the file before
  # its Content-Length: the bytes already written are thrown away, not
  # added to.
  def test_a_connection_that_breaks_off_is_tried_again_from_the_start
    answers = [[200, { "Content-Length" => BODY.bytesize.to_s }, BODY[0, 1000]], [200, {}, BODY]]
    server = LoopbackServer.new({ "/file" => -> { answers.shift } })
    Dir.mktmpdir do |dir|
      to = File.join(dir, "f")

      Fledge::Download.save(server.url("/file"), to:, sha256: SHA, waits: [0])

      assert_equal BODY, File.read(to)
      assert_equal 2, server.requests.size
    end
  ensure
    server&.stop
  end

  # A body that arrives a few bytes at a time, as a connection to a CDN
  # that has all but stopped sends it, which no single read's timeout
  # catches: slower than the pace allows over its window, it is given up
  # and tried again, as curl's --speed-limit and --speed-time, and
  # Cargo's http.low-speed-limit, give one up.
  def test_a_download_that_trickles_is_given_up_and_tried_again
    trickle = -> (client) { BODY.each_char.each_slice(10) { |bytes| client.write(bytes.join) && sleep(0.02) } }
    answers = [[200, { "Content-Length" => BODY.bytesize.to_s }, trickle], [200, {}, BODY]]
    server = LoopbackServer.new({ "/file" => -> { answers.shift } })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      to = File.join(dir, "f")
      pace = Fledge::Download::Pace.new(bytes: 100_000, seconds: 0.3, report: 60)

      Fledge::Download.save(server.url("/file"), to:, sha256: SHA, waits: [0], log:, pace:)

      assert_equal BODY, File.read(to)
      assert_equal 2, server.requests.size
      assert_equal "could not download #{server.url('/file')}: less than 100000 bytes a second for 0.3 seconds; " \
        "trying again in 0 seconds (2 of 2)\n", log.string
    end
  ensure
    server&.stop
  end

  # A body that stops altogether: the window is the longest any one read
  # may wait, too.
  def test_a_download_that_stops_is_given_up_within_its_window_and_tried_again
    stop = -> (client) { client.write(BODY[0, 1000]) && sleep(10) }
    answers = [[200, { "Content-Length" => BODY.bytesize.to_s }, stop], [200, {}, BODY]]
    server = LoopbackServer.new({ "/file" => -> { answers.shift } })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      to = File.join(dir, "f")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Fledge::Download.save(server.url("/file"), to:, sha256: SHA, waits: [0], log:, pace: Fledge::Download::Pace.new(bytes: 1, seconds: 0.3, report: 60))

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
      assert_equal BODY, File.read(to)
      assert_match(/\Acould not download #{Regexp.escape(server.url('/file'))}: .*; trying again in 0 seconds \(2 of 2\)\n\z/, log.string)
    end
  ensure
    server&.stop
  end

  def test_a_download_that_never_gets_faster_fails_with_the_pace_it_missed
    trickle = -> (client) { 100.times { client.write("x") && sleep(0.02) } }
    server = LoopbackServer.new({ "/file" => [200, { "Content-Length" => BODY.bytesize.to_s }, trickle] })
    Dir.mktmpdir do |dir|
      pace = Fledge::Download::Pace.new(bytes: 100_000, seconds: 0.2, report: 60)
      error = assert_raises(Fledge::Download::Unreachable) do
        Fledge::Download.save(server.url("/file"), to: File.join(dir, "f"), sha256: SHA, waits: [0], pace:)
      end

      assert_equal "could not download #{server.url('/file')}: less than 100000 bytes a second for 0.2 seconds", error.message
      assert_equal 2, server.requests.size
      assert_empty Dir.children(dir)
    end
  ensure
    server&.stop
  end

  # A download that takes longer than the pace's report says on the log
  # how far it got, so a person or a CI log sees it move.
  def test_a_long_download_reports_its_progress_on_the_log
    slowly = -> (client) { BODY.each_char.each_slice(14_000) { |bytes| client.write(bytes.join) && sleep(0.05) } }
    server = LoopbackServer.new({ "/runtime.tar.gz" => [200, { "Content-Length" => BODY.bytesize.to_s }, slowly] })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      pace = Fledge::Download::Pace.new(bytes: 1, seconds: 5, report: 0.1)
      Fledge::Download.save(server.url("/runtime.tar.gz"), to: File.join(dir, "f"), sha256: SHA, log:, pace:)

      lines = log.string.lines(chomp: true)
      refute_empty lines
      lines.each { |line| assert_match(%r{\Aruntime\.tar\.gz: \d+\.\d MB of 0\.1 MB \(\d+%\), \d+\.\d MB/s\z}, line) }
    end
  ensure
    server&.stop
  end

  def test_a_download_reports_progress_without_a_length_too
    slowly = -> (client) { BODY.each_char.each_slice(14_000) { |bytes| client.write(bytes.join) && sleep(0.05) } }
    server = LoopbackServer.new({ "/f" => [200, {}, slowly] })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      Fledge::Download.save(server.url("/f"), to: File.join(dir, "f"), sha256: SHA, log:, pace: Fledge::Download::Pace.new(bytes: 1, seconds: 5, report: 0.1))
    end

    refute_empty log.string
    log.string.lines(chomp: true).each { |line| assert_match(%r{\Af: \d+\.\d MB, \d+\.\d MB/s\z}, line) }
  ensure
    server&.stop
  end

  # curl gives up below 1 byte a second for 30 seconds once asked to,
  # and Cargo below 10; Fledge's files are tens to hundreds of
  # megabytes, where 10 kB a second already means hours.
  def test_a_download_slower_than_ten_kilobytes_a_second_for_thirty_seconds_is_stalled_and_reports_every_fifteen
    assert_equal Fledge::Download::Pace.new(bytes: 10_000, seconds: 30, report: 15), Fledge::Download::PACE
  end

  def test_a_server_still_failing_after_every_wait_fails_with_its_last_answer
    server = LoopbackServer.new({ "/file" => [502, {}, ""] })
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Download::Unavailable) do
        Fledge::Download.save(server.url("/file"), to: File.join(dir, "f"), sha256: SHA, waits: [0, 0])
      end

      assert_equal "could not download #{server.url('/file')}: 502 X", error.message
      assert_equal 3, server.requests.size
      assert_empty Dir.children(dir)
    end
  ensure
    server&.stop
  end

  def test_an_unreachable_server_is_tried_again_and_then_fails
    Dir.mktmpdir do |dir|
      log = StringIO.new
      error = assert_raises(Fledge::Download::Unreachable) do
        Fledge::Download.save("http://127.0.0.1:1/file", to: File.join(dir, "f"), sha256: SHA, waits: [0], log:)
      end

      assert_match(%r{\Acould not download http://127.0.0.1:1/file: }, error.message)
      assert_equal 1, log.string.lines.size
      assert_empty Dir.children(dir)
    end
  end

  # A missing file, a refusal, another 4xx, and a file whose SHA-256 is
  # not the pin's would answer the same a moment later.
  def test_a_permanent_failure_is_not_tried_again
    server = LoopbackServer.new({
      "/gone" => [404, {}, ""],
      "/denied" => [403, {}, ""],
      "/bad" => [400, {}, ""],
      "/changed" => [200, {}, "#{BODY}, changed"],
    })
    log = StringIO.new
    Dir.mktmpdir do |dir|
      %w[/gone /denied /bad /changed].each do |path|
        assert_raises(Fledge::Error) { Fledge::Download.save(server.url(path), to: File.join(dir, "f"), sha256: SHA, waits: [0, 0], log:) }
      end

      assert_equal %w[/gone /denied /bad /changed], server.requests
      assert_empty log.string
      assert_empty Dir.children(dir)
    end
  ensure
    server&.stop
  end

  # Bundler's default, three retries (BUNDLE_RETRY), with waits that
  # double from two seconds, as Fledge::Dmg's do.
  def test_a_download_waits_two_four_and_eight_seconds
    assert_equal [2, 4, 8], Fledge::Download::WAITS
  end

  def test_only_http_and_https_are_downloaded
    error = assert_raises(Fledge::Error) { Fledge::Download.read("file:///etc/passwd") }

    assert_equal "file:///etc/passwd is not an http or https URL", error.message
  end
end
