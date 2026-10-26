# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/zip_reader"
require "open3"

class ZipTest < Minitest::Test
  # 2023-11-14 22:13:20 UTC.
  MTIME = 1_700_000_000
  COMPRESSIBLE = ("puts 'hello'\n" * 200).freeze
  NOISE = Random.new(1).bytes(4096).freeze

  def entries
    [
      Fledge::Entry.directory("top"),
      Fledge::Entry.file("top/hello.exe", NOISE, mode: 0o755),
      Fledge::Entry.file("top/empty", ""),
      Fledge::Entry.directory("top/app"),
      Fledge::Entry.file("top/app/main.rb", COMPRESSIBLE),
      Fledge::Entry.file("top/Ünïcödé 日本.txt", "u"),
      Fledge::Entry.file("top/#{(['x' * 40] * 3).join('/')}/deep.rb", "deep"),
    ]
  end

  def write(dir, name = "a.zip", mtime: MTIME)
    path = File.join(dir, name)
    Fledge::Zip.write(path, mtime:) { |zip| entries.each { |entry| zip.add(entry) } }
  end

  def members(dir)
    ZipReader.read(write(dir)).to_h { |member| [member.name, member] }
  end

  def test_entries_round_trip_with_folders_marked_by_a_trailing_slash
    Dir.mktmpdir do |dir|
      path = write(dir)

      assert_equal File.join(dir, "a.zip"), path
      found = ZipReader.read(path)
      assert_equal(entries.map { |entry| (entry.type == :directory) ? "#{entry.path}/" : entry.path }, found.map(&:name))
      entries.zip(found).each { |entry, member| assert_equal entry.content.b, member.data.b, entry.path }
    end
  end

  def test_names_are_flagged_as_utf8_so_windows_reads_them_as_written
    Dir.mktmpdir do |dir|
      found = members(dir)

      assert(found.each_value.all? { |member| member.flags & 0x0800 != 0 })
      assert_equal "u", found.fetch("top/Ünïcödé 日本.txt").data
    end
  end

  def test_compressible_files_are_deflated_and_the_rest_stored
    Dir.mktmpdir do |dir|
      found = members(dir)

      main = found.fetch("top/app/main.rb")
      assert_equal 8, main.method
      assert_operator main.compressed_size, :<, COMPRESSIBLE.bytesize / 10
      assert_equal 0, found.fetch("top/hello.exe").method
      assert_equal NOISE.bytesize, found.fetch("top/hello.exe").compressed_size
      assert_equal [0, 0, 0], found.fetch("top/empty").then { |empty| [empty.method, empty.size, empty.crc] }
      assert_equal [0, 0], found.fetch("top/").then { |folder| [folder.method, folder.size] }
    end
  end

  # Made by Unix, with the mode in the high half of the external
  # attributes, as Info-ZIP writes it, so unzip keeps an executable bit;
  # folders also carry MS-DOS's directory attribute.
  def test_unix_modes_and_the_dos_folder_attribute_are_recorded
    Dir.mktmpdir do |dir|
      found = members(dir)

      assert(found.each_value.all? { |member| member.made_by == 0x031E })
      assert_equal (0o100755 << 16), found.fetch("top/hello.exe").external
      assert_equal (0o100644 << 16), found.fetch("top/app/main.rb").external
      assert_equal (0o040755 << 16) | 0x10, found.fetch("top/app/").external
    end
  end

  def test_times_are_the_given_mtime_in_utc_as_ms_dos_records_them
    Dir.mktmpdir do |dir|
      member = members(dir).fetch("top/app/main.rb")

      assert_equal ((2023 - 1980) << 9) | (11 << 5) | 14, member.dos_date
      assert_equal (22 << 11) | (13 << 5) | (20 / 2), member.dos_time
    end
  end

  def test_a_time_before_1980_becomes_ms_doses_earliest
    Dir.mktmpdir do |dir|
      member = ZipReader.read(write(dir, mtime: 0)).first

      assert_equal [(1 << 5) | 1, 0], [member.dos_date, member.dos_time]
    end
  end

  def test_a_time_after_2107_becomes_ms_doses_latest
    Dir.mktmpdir do |dir|
      member = ZipReader.read(write(dir, mtime: Time.utc(2200, 1, 1).to_i)).first

      assert_equal [(127 << 9) | (12 << 5) | 31, (23 << 11) | (59 << 5) | 29], [member.dos_date, member.dos_time]
    end
  end

  def test_the_extension_is_zip
    assert_equal ".zip", Fledge::Zip.extension
    assert_equal ".tar.gz", Fledge::TarGz.extension
  end

  def test_the_archive_is_reproducible_for_a_fixed_mtime
    Dir.mktmpdir do |one|
      Dir.mktmpdir do |two|
        assert_equal File.binread(write(one)), File.binread(write(two))
      end
    end
  end

  def test_a_symlink_is_refused_because_windows_cannot_unpack_one
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) do
        Fledge::Zip.write(File.join(dir, "l.zip")) { |zip| zip.add(Fledge::Entry.symlink("top/link", "elsewhere")) }
      end

      assert_equal "top/link is a symbolic link, which a .zip for Windows cannot hold. " \
        "Replace it with what it points to.", error.message
    end
  end

  # Zip64 would lift the limit; Fledge's archives are far from it.
  def test_more_entries_than_a_zip_without_zip64_holds_are_refused
    Dir.mktmpdir do |dir|
      error = assert_raises(Fledge::Error) do
        Fledge::Zip.write(File.join(dir, "many.zip")) do |zip|
          (Fledge::Zip::MAX_ENTRIES + 1).times { |index| zip.add(Fledge::Entry.directory("d#{index}")) }
        end
      end

      assert_equal "a .zip without Zip64 holds at most 65534 files and folders", error.message
    end
  end

  def test_unzip_tests_what_the_writer_writes
    skip "unzip is not on PATH" unless system("unzip", "-v", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      write(dir)
      out, status = Open3.capture2e("unzip", "-t", "a.zip", chdir: dir)

      assert_predicate status, :success?, out
      assert_includes out, "No errors detected"
    end
  end

  # macOS's tar and Windows' tar.exe are bsdtar, which reads a .zip.
  def test_bsdtar_unpacks_what_the_writer_writes
    bsdtar = %w[bsdtar tar].find do |tool|
      out, = Open3.capture2e(tool, "--version")
      out.include?("bsdtar")
    rescue SystemCallError
      false
    end
    skip "no bsdtar on PATH" unless bsdtar

    Dir.mktmpdir do |dir|
      write(dir)
      out, status = Open3.capture2e(bsdtar, "-xf", "a.zip", chdir: dir)

      assert_predicate status, :success?, out
      assert_unpacked(dir)
      assert_equal 0o755, File.stat(File.join(dir, "top/hello.exe")).mode & 0o777 unless Gem.win_platform?
    end
  end

  # Expand-Archive is what a person on Windows has without installing
  # anything, and it reads the archive with .NET's own zip reader.
  def test_windows_expand_archive_unpacks_what_the_writer_writes
    skip "Expand-Archive is Windows PowerShell's" unless Gem.win_platform?

    Dir.mktmpdir do |dir|
      write(dir)
      out, status = Open3.capture2e("powershell", "-NoProfile", "-NonInteractive", "-Command",
        "$ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath a.zip -DestinationPath .", chdir: dir)

      assert_predicate status, :success?, out
      assert_unpacked(dir)
    end
  end

  def assert_unpacked(dir)
    assert_equal COMPRESSIBLE, File.read(File.join(dir, "top/app/main.rb"))
    assert_equal NOISE, File.binread(File.join(dir, "top/hello.exe"))
    assert_equal "u", File.read(File.join(dir, "top/Ünïcödé 日本.txt"))
    assert_equal "deep", File.read(File.join(dir, "top/#{(['x' * 40] * 3).join('/')}/deep.rb"))
    assert_equal 0, File.size(File.join(dir, "top/empty"))
  end
end
