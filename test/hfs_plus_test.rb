# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/disk_images"
require "open3"

# Fledge::HfsPlus, read back by TN1150's layout (test/support/disk_images.rb)
# on any computer, and, on a Mac, attached by hdiutil and checked by
# Apple's fsck_hfs, the oracles.
class HfsPlusTest < Minitest::Test
  LAUNCHER = "#!/bin/sh\necho hi\n"

  def volume(entries, name: "My App")
    io = StringIO.new("".b)
    hfs = Fledge::HfsPlus.new(io, name:, mtime: 1_700_000_000)
    entries.each { |entry| hfs.add(entry) }
    size = hfs.finish
    [io.string, size]
  end

  def app
    [
      Fledge::Entry.directory("My App.app"),
      Fledge::Entry.file("My App.app/Contents/MacOS/My App", LAUNCHER, mode: 0o755),
      Fledge::Entry.file("My App.app/Contents/Info.plist", "<plist/>\n"),
      Fledge::Entry.symlink("My App.app/Contents/MacOS/lib", "../Resources/lib"),
      Fledge::Entry.file("My App.app/Contents/Resources/big", "x" * 10_000),
      Fledge::Entry.file("My App.app/Contents/Resources/empty", ""),
      Fledge::Entry.symlink("Applications", "/Applications"),
    ]
  end

  def test_the_header_names_a_case_sensitive_volume_of_whole_blocks_and_its_copy_ends_it
    bytes, size = volume(app)
    hfs = DiskImages::Hfs.new(bytes)

    assert_equal ["HX", 5, 4096], [hfs.signature, hfs.version, hfs.block_size]
    assert_equal size, bytes.bytesize
    assert_equal size, hfs.total_blocks * 4096
    assert_equal [6, 4], [hfs.file_count, hfs.folder_count]
    assert_equal hfs.header, bytes.byteslice(size - 1024, 512)
  end

  def test_every_item_is_in_the_catalog_with_its_mode_and_bytes
    hfs = DiskImages::Hfs.new(volume(app).first)

    launcher = hfs.items.fetch("My App.app/Contents/MacOS/My App")
    assert_equal [:file, 0o100755, LAUNCHER], [launcher[:type], launcher[:mode], launcher[:content]]
    assert_equal ["x" * 10_000, 0o100644], hfs.items.fetch("My App.app/Contents/Resources/big").values_at(:content, :mode)
    assert_equal "", hfs.items.fetch("My App.app/Contents/Resources/empty")[:content]
    folder = hfs.items.fetch("My App.app/Contents")
    assert_equal [:folder, 0o040755, 3, 2], folder.values_at(:type, :mode, :valence, :folders)
    assert_equal 0x0010, folder[:flags] & 0x0010
    assert_equal "My App", hfs.keys.find { |parent, _| parent == 1 }&.last
  end

  # A symbolic link is a file of type slnk, creator rhap, whose data is
  # its target (TN1150, "Symbolic Links").
  def test_a_symlink_is_a_file_of_type_slnk_holding_its_target
    hfs = DiskImages::Hfs.new(volume(app).first)

    link = hfs.items.fetch("Applications")
    assert_equal [0o120755, "slnkrhap", "/Applications"], [link[:mode], link[:user_info], link[:content]]
  end

  # A B-tree's records are in key order: by parent, then by the name's
  # UTF-16 code units, as an HFSX volume compares them; a thread record
  # (an empty name) first under each ID.
  def test_the_catalog_is_in_binary_key_order_with_a_thread_for_every_item
    entries = %w[b B a ä Z].map { |name| Fledge::Entry.file("dir/#{name}", name) }
    hfs = DiskImages::Hfs.new(volume(entries).first)

    keys = hfs.keys.map { |parent, name| [parent, name.encode(Encoding::UTF_16BE).b] }
    assert_equal keys.sort, keys
    assert_equal ["B", "Z", "a", "ä", "b"], hfs.keys.select { |parent, _| parent == hfs.items.fetch("dir")[:id] && true }.map(&:last).reject(&:empty?)
    assert_equal hfs.items.size, hfs.keys.count { |_, name| name.empty? }
  end

  # HFS Plus keeps names decomposed (TN1150, "Unicode Subtleties"), and a
  # colon, which macOS shows as a slash, as a slash.
  def test_names_are_decomposed_and_colons_are_stored_as_slashes
    hfs = DiskImages::Hfs.new(volume([Fledge::Entry.file("é:b", "1")]).first)

    assert_equal ["é/b"], hfs.items.keys.reject(&:empty?)
  end

  def test_folders_it_needs_are_added_and_a_folder_added_twice_is_one
    hfs = DiskImages::Hfs.new(volume([Fledge::Entry.file("a/b/c", "1"), Fledge::Entry.directory("a")]).first)

    assert_equal ["", "a", "a/b", "a/b/c"], hfs.items.keys.sort
  end

  def test_a_path_twice_a_file_as_a_folder_and_a_long_name_are_refused
    hfs = Fledge::HfsPlus.new(StringIO.new("".b), name: "V")
    hfs.add(Fledge::Entry.file("a", "1"))

    assert_raises(Fledge::Error) { hfs.add(Fledge::Entry.file("a", "2")) }
    assert_match(/is not a folder/, assert_raises(Fledge::Error) { hfs.add(Fledge::Entry.file("a/b", "2")) }.message)
    assert_match(/longer than/, assert_raises(Fledge::Error) { hfs.add(Fledge::Entry.file("n" * 256, "")) }.message)
  end

  # Enough files to fill many leaf nodes and an index level: the catalog
  # still reads in order, and on a Mac fsck_hfs accepts it.
  def test_a_catalog_of_many_nodes_has_an_index_and_stays_in_order
    entries = Array.new(3000) { |index| Fledge::Entry.file("lib/file-#{index}.rb", "# #{index}\n") }
    bytes, = volume(entries)
    hfs = DiskImages::Hfs.new(bytes)

    assert_equal 3002, hfs.items.size
    keys = hfs.keys.map { |parent, name| [parent, name.encode(Encoding::UTF_16BE).b] }
    assert_equal keys.sort, keys
    assert_operator hfs.catalog_depth, :>=, 2
  end

  def test_macos_mounts_and_checks_the_volume
    skip "hdiutil and fsck_hfs are macOS's" unless RUBY_PLATFORM.include?("darwin")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "volume.hfs")
      File.binwrite(path, volume(app + Array.new(2000) { |index| Fledge::Entry.file("many/#{index}", index.to_s) }).first)
      out, status = Open3.capture2e("hdiutil", "attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", path)
      assert_predicate status, :success?, out
      device = out[%r{/dev/disk\d+}]
      begin
        out, status = Open3.capture2e("fsck_hfs", "-fn", device)
        assert_predicate status, :success?, out
        assert_includes out, "appears to be OK"
      ensure
        system("hdiutil", "detach", "-quiet", device.to_s)
      end
      DiskImages.mounted(path, raw: true) do |mount|
        assert_equal LAUNCHER, File.read(File.join(mount, "My App.app/Contents/MacOS/My App"))
        assert File.executable?(File.join(mount, "My App.app/Contents/MacOS/My App"))
        assert_equal "/Applications", File.readlink(File.join(mount, "Applications"))
        assert_equal "../Resources/lib", File.readlink(File.join(mount, "My App.app/Contents/MacOS/lib"))
        assert_equal "1999", File.read(File.join(mount, "many/1999"))
      end
    end
  end
end
