# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "zlib"

# Fledge::Squashfs, checked by squashfs-tools-ng's format document on any
# computer, and on Linux by squashfs-tools' own unsquashfs, the oracle,
# which CI installs on every Linux it tests on (FLEDGE_REQUIRE_UNSQUASHFS
# turns its absence there into a failure).
class SquashfsTest < Minitest::Test
  BIG = Random.new(7).bytes(200_000) + ("a" * 150_000)

  def entries
    [
      Fledge::Entry.file("AppRun.real", "#!/bin/sh\necho hi\n", mode: 0o755),
      Fledge::Entry.symlink("AppRun", "AppRun.real"),
      Fledge::Entry.file("big", BIG),
      Fledge::Entry.file("empty", ""),
      Fledge::Entry.file("share/icons/hicolor/16x16/apps/x.png", "png"),
      Fledge::Entry.directory("empty-folder"),
      *Array.new(300) { |index| Fledge::Entry.file("lib/many/#{format('%04d', index)}.rb", "# #{index}\n" * 20) },
    ]
  end

  def write(io, list = entries)
    squashfs = Fledge::Squashfs.new(io, mtime: 1_700_000_000)
    list.each { |entry| squashfs.add(entry) }
    squashfs.finish
  end

  def superblock(bytes)
    bytes.unpack("VVVVVvvvvvvQ<Q<Q<Q<Q<Q<Q<Q<")
  end

  def test_the_superblock_says_squashfs_4_0_zlib_with_every_inode
    io = StringIO.new("".b)
    size = write(io)
    magic, inodes, mtime, block, fragments, compressor, log, flags, ids, major, minor, _, used = superblock(io.string)

    assert_equal [0x73717368, 4, 0], [magic, major, minor]
    assert_equal [entries.size + 8, 1_700_000_000, 131_072, 17, 1, 1], [inodes, mtime, block, log, compressor, ids]
    assert_equal 0x0200, flags
    assert_operator fragments, :>=, 1
    assert_equal 0, size % 4096
    assert_operator used, :<=, size
  end

  # A file's full blocks are compressed one by one where they begin, and
  # its tail goes into a fragment.
  def test_a_files_full_blocks_are_compressed_where_its_data_begins
    io = StringIO.new("".b)
    write(io, [Fledge::Entry.file("big", BIG)])

    random = io.string.byteslice(96, 131_072).to_s
    assert_equal BIG.byteslice(0, 131_072), random
  end

  def test_offsets_count_from_where_it_begins_so_it_can_follow_a_runtime
    io = StringIO.new("".b)
    io.write("RUNTIME")
    write(io)

    assert_equal 0x73717368, io.string.byteslice(7, 4).to_s.unpack1("V")
  end

  def test_a_path_twice_a_file_as_a_folder_and_a_long_name_are_refused
    squashfs = Fledge::Squashfs.new(StringIO.new("".b))
    squashfs.add(Fledge::Entry.file("a", "1"))

    assert_raises(Fledge::Error) { squashfs.add(Fledge::Entry.file("a", "2")) }
    assert_match(/not a folder/, assert_raises(Fledge::Error) { squashfs.add(Fledge::Entry.file("a/b", "2")) }.message)
    assert_match(/longer name/, assert_raises(Fledge::Error) { squashfs.add(Fledge::Entry.file("n" * 257, "")) }.message)
  end

  def test_unsquashfs_reads_back_every_file_mode_and_link
    unsquashfs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |folder| File.join(folder, "unsquashfs") }.find { |path| File.executable?(path) }
    unless unsquashfs
      flunk "no unsquashfs on PATH" if ENV["FLEDGE_REQUIRE_UNSQUASHFS"]
      skip "squashfs-tools' unsquashfs is the oracle; install it to run this"
    end

    Dir.mktmpdir do |dir|
      image = File.join(dir, "image.squashfs")
      File.open(image, "wb") { |io| write(io) }
      out, status = Open3.capture2e(unsquashfs, "-no-progress", "-d", File.join(dir, "root"), image)
      assert_predicate status, :success?, out
      root = File.join(dir, "root")

      assert_equal BIG, File.binread(File.join(root, "big"))
      assert_equal "AppRun.real", File.readlink(File.join(root, "AppRun"))
      assert_equal 0o755, File.stat(File.join(root, "AppRun.real")).mode & 0o777
      assert_equal 0o644, File.stat(File.join(root, "big")).mode & 0o777
      assert_equal "", File.read(File.join(root, "empty"))
      assert_empty Dir.children(File.join(root, "empty-folder"))
      assert_equal 300, Dir.children(File.join(root, "lib/many")).size
      assert_equal "# 299\n" * 20, File.read(File.join(root, "lib/many/0299.rb"))
    end
  end
end
