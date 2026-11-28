# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "tmpdir"
require_relative "../test_helper"
require_relative "../support/loopback_server"
require_relative "../../tasks/pin_watch"

# PinWatch::Fetch#member_sha256, with the real zstd and tar, on a
# Zstandard-compressed tarball shaped as LLVM's release archive is: the
# file the move of llvm-readobj hashes.
class PinMemberTest < Minitest::Test
  MEMBER = "clang+llvm-9.9.9-x86_64-pc-windows-msvc/bin/llvm-readobj.exe"

  def tarball(folder)
    FileUtils.mkdir_p(File.join(folder, File.dirname(MEMBER)))
    File.binwrite(File.join(folder, MEMBER), "the program\r\n")
    File.binwrite(File.join(folder, File.dirname(MEMBER), "clang.exe"), "another program")
    archive = File.join(folder, "llvm.tar.zst")
    tar = Open3.pipeline(["tar", "-cf", "-", "-C", folder, MEMBER.split("/").first], ["zstd", "-q", "--long=31", "-o", archive])
    assert tar.all?(&:success?), "could not write #{archive}"
    File.binread(archive)
  end

  def test_hashes_one_file_of_a_zstandard_tarball
    skip "no zstd on this computer" unless system("zstd", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |folder|
      server = LoopbackServer.new("/llvm.tar.zst" => [200, {}, tarball(folder)])
      fetch = PinWatch::Fetch.new(timeout: 5)

      assert_equal Digest::SHA256.hexdigest("the program\r\n"), fetch.member_sha256(server.url("/llvm.tar.zst"), MEMBER)
      error = assert_raises(PinWatch::Error) { fetch.member_sha256(server.url("/llvm.tar.zst"), "llvm/bin/none.exe") }
      assert_includes error.message, "holds no llvm/bin/none.exe"
    ensure
      server&.stop
    end
  end
end
