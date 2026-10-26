# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

class TarGzTest < Minitest::Test
  LONG = "top/#{(['x' * 90] * 3).join('/')}/file.rb".freeze
  LONG_NAME = "top/#{'y' * 120}.rb".freeze

  def entries
    [
      Fledge::Entry.directory("top"),
      Fledge::Entry.file("top/run", "#!/bin/sh\necho hi\n", mode: 0o755),
      Fledge::Entry.file("top/empty", ""),
      Fledge::Entry.symlink("top/link", "run"),
      Fledge::Entry.symlink("top/far", "#{'z/' * 60}run"),
      Fledge::Entry.file(LONG, "x" * 1000),
      Fledge::Entry.file(LONG_NAME, "y"),
      Fledge::Entry.file("top/Ünïcödé 日本.txt", "u".b),
    ]
  end

  def write(dir)
    path = File.join(dir, "a.tar.gz")
    Fledge::TarGz.write(path, mtime: 1_700_000_000) { |tar| entries.each { |entry| tar.add(entry) } }
  end

  def read(path)
    found = []
    Fledge::TarGz.each_entry(path) { |entry| found << entry }
    found
  end

  def test_entries_round_trip_with_modes_links_and_long_paths
    Dir.mktmpdir do |dir|
      path = write(dir)

      assert_equal File.join(dir, "a.tar.gz"), path
      read(path).zip(entries).each do |actual, expected|
        assert_equal [expected.path, expected.type, expected.mode, expected.link],
          [actual.path, actual.type, actual.mode, actual.link]
        assert_equal expected.content.b, actual.content.b
      end
      assert_equal entries.size, read(path).size
    end
  end

  def test_the_archive_is_reproducible_for_a_fixed_mtime
    Dir.mktmpdir do |one|
      Dir.mktmpdir do |two|
        assert_equal File.binread(write(one)), File.binread(write(two))
      end
    end
  end

  def test_system_tar_reads_what_the_writer_writes
    skip "tar is not on PATH" unless system("tar", "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      path = write(dir)
      out, status = Open3.capture2e("tar", "-xzf", path, "-C", dir)

      assert_predicate status, :success?, out
      assert_equal "x" * 1000, File.read(File.join(dir, LONG))
      assert_equal "y", File.read(File.join(dir, LONG_NAME))
      unless Gem.win_platform?
        assert_equal "run", File.readlink(File.join(dir, "top/link"))
        assert_equal 0o755, File.stat(File.join(dir, "top/run")).mode & 0o777
      end
    end
  end

  def test_the_reader_reads_what_system_tar_writes
    skip "tar is not on PATH" unless system("tar", "--version", out: File::NULL, err: File::NULL)
    skip "symlinks need privileges on Windows" if Gem.win_platform?

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "src/#{'d' * 120}"))
      File.write(File.join(dir, "src/#{'d' * 120}/#{'f' * 120}"), "deep")
      File.symlink("x", File.join(dir, "src/l"))
      archive = File.join(dir, "sys.tar.gz")
      out, status = Open3.capture2e("tar", "-czf", archive, "-C", dir, "src")
      assert_predicate status, :success?, out

      by_path = read(archive).to_h { |entry| [entry.path, entry] }

      assert_equal "deep", by_path.fetch("src/#{'d' * 120}/#{'f' * 120}").content
      assert_equal "x", by_path.fetch("src/l").link
    end
  end

  def test_a_file_that_is_not_gzip_is_an_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "not.tar.gz")
      File.write(path, "plain text")

      error = assert_raises(Fledge::Error) { read(path) }
      assert_match(/is not a \.tar\.gz archive/, error.message)
    end
  end

  # A one-entry tar stream, written independently of Fledge::TarGz.
  def ustar(name, typeflag)
    fields = [name, "0000644", "0000000", "0000000", "00000000000", "00000000000", " " * 8, typeflag, "", "ustar", "00"]
    header = fields.pack("a100a8a8a8a12a12a8a1a100a6a2").ljust(512, "\0")
    header[148, 8] = format("%06o\0 ", header.bytes.sum)
    header + ("\0" * 1024)
  end

  def gzip(dir, name, bytes)
    path = File.join(dir, name)
    Zlib::GzipWriter.open(path) { |gz| gz.write(bytes) }
    path
  end

  def test_a_hand_written_ustar_entry_reads
    Dir.mktmpdir do |dir|
      entry, = read(gzip(dir, "ok.tar.gz", ustar("plain", "0")))

      assert_equal ["plain", :file, 0o644, ""], [entry.path, entry.type, entry.mode, entry.content]
    end
  end

  def test_a_damaged_header_is_an_error
    Dir.mktmpdir do |dir|
      bytes = ustar("plain", "0")
      bytes.setbyte(0, "q".ord)

      error = assert_raises(Fledge::Error) { read(gzip(dir, "bad.tar.gz", bytes)) }
      assert_equal "the archive is damaged: a header's checksum does not match", error.message
    end
  end

  def test_unsafe_paths_and_unsupported_entries_are_refused
    Dir.mktmpdir do |dir|
      unsafe = assert_raises(Fledge::Error) { read(gzip(dir, "u.tar.gz", ustar("../evil", "0"))) }
      hard = assert_raises(Fledge::Error) { read(gzip(dir, "h.tar.gz", ustar("hard", "1"))) }

      assert_includes unsafe.message, "is not a safe path"
      assert_equal "\"hard\" is a kind of file an app cannot hold (tar type \"1\")", hard.message
    end
  end
end
