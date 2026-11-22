# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "digest"
require_relative "../support/loopback_server"

# Fledge::Download across processes, each a Ruby of its own; the rest of
# it is test/download_test.rb's, in one process.
class DownloadProcessesTest < Minitest::Test
  BODY = ("runtime bytes " * 10_000).freeze
  SHA = Digest::SHA256.hexdigest(BODY)

  # Two builds on one computer that need one pinned file at once, as
  # runtime builds sharing a cache do: the first downloads it, the
  # second waits for it, says so, and downloads nothing.
  def test_two_processes_saving_one_file_at_once_download_it_once
    slowly = -> (client) { BODY.each_char.each_slice(14_000) { |bytes| client.write(bytes.join) && sleep(0.1) } }
    server = LoopbackServer.new({ "/runtime.tar.gz" => [200, {}, slowly] })
    script = "require ARGV[0]; Fledge::Download.save(ARGV[1], to: ARGV[2], sha256: ARGV[3], log: $stdout)"
    Dir.mktmpdir do |dir|
      to = File.join(dir, "cache", "runtime.tar.gz")
      command = [RbConfig.ruby, "-e", script, File.expand_path("../../lib/fledge/download", __dir__), server.url("/runtime.tar.gz"), to, SHA]
      outputs = Array.new(2) { IO.popen(command, err: %i[child out]) }.map(&:read)

      assert_equal %w[/runtime.tar.gz], server.requests
      assert_equal BODY, File.read(to)
      assert_equal ["runtime.tar.gz"], Dir.children(File.dirname(to)).reject { |name| name.end_with?(".lock") }
      assert_equal 1, outputs.count { |out| out.include?("waiting for another download of runtime.tar.gz to finish") }, outputs.inspect
    end
  ensure
    server&.stop
  end
end
