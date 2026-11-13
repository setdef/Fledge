# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# How the Android runtime links, at each start, the paths an app's Ruby
# looks for a file at to the native libraries the installer extracted
# (runtime/mobile/library_links.c), compiled with this computer's C
# compiler: ROOT/fledge.links names, for each ABI, a library in the
# native library folder and the path under ROOT to link to it.
class MobileLibraryLinksTest < Minitest::Test
  MOBILE = File.expand_path("../../runtime/mobile", __dir__)

  # The program: HOST ROOT FOLDER ABI calls fledge_link_libraries and
  # exits with what it returns.
  HOST = <<~C
    #include "mobile.h"

    int main(int argc, char **argv) {
        if (argc != 4) return 2;
        return fledge_link_libraries(argv[1], argv[2], argv[3]);
    }
  C

  def setup
    skip "the Android runtime's links are POSIX; Windows is not" if Gem.win_platform?
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)

    @dir = File.realpath(Dir.mktmpdir)
    @root = File.join(@dir, "root")
    @folder = File.join(@dir, "native-1")
    FileUtils.mkdir_p([@root, @folder])
    File.write(File.join(@folder, "libfledgeext.adder.adder.adder.so"), "")
    @host = compile
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_each_line_of_this_abi_becomes_a_link_to_its_library
    links("x86_64\tlibfledgeext.adder.adder.adder.so\tgems/adder/lib/adder/adder.so",
      "arm64-v8a\tlibfledgeext.adder.adder.adder.so\tgems/adder/arm64/adder/adder.so")

    assert_equal [0, ""], run_host("x86_64")
    assert_equal File.join(@folder, "libfledgeext.adder.adder.adder.so"), File.readlink(File.join(@root, "gems/adder/lib/adder/adder.so"))
    refute File.exist?(File.join(@root, "gems/adder/arm64"))
  end

  def test_a_link_follows_the_folder_when_it_moves
    links("x86_64\tlibfledgeext.adder.adder.adder.so\tlib/adder.so")
    run_host("x86_64")
    moved = File.join(@dir, "native-2")
    FileUtils.mv(@folder, moved)
    @folder = moved

    assert_equal [0, ""], run_host("x86_64")
    assert_equal File.join(moved, "libfledgeext.adder.adder.adder.so"), File.readlink(File.join(@root, "lib/adder.so"))
  end

  def test_a_missing_library_removes_its_old_link_and_says_so
    links("x86_64\tlibfledgeext.adder.adder.adder.so\tlib/adder.so")
    run_host("x86_64")
    File.delete(File.join(@folder, "libfledgeext.adder.adder.adder.so"))

    status, err = run_host("x86_64")

    assert_equal 1, status
    assert_includes err, "libfledgeext.adder.adder.adder.so"
    refute File.symlink?(File.join(@root, "lib/adder.so"))
  end

  def test_a_path_outside_the_root_is_refused
    links("x86_64\tlibfledgeext.adder.adder.adder.so\t../outside.so", "x86_64\tlibfledgeext.adder.adder.adder.so\t/tmp/abs.so",
      "x86_64\t../libc.so\tlib/c.so")

    status, err = run_host("x86_64")

    assert_equal 3, status
    assert_includes err, "../outside.so"
    refute File.exist?(File.join(@dir, "outside.so"))
    refute File.symlink?(File.join(@root, "lib/c.so"))
  end

  def test_no_list_links_nothing
    assert_equal [0, ""], run_host("x86_64")
    assert_equal [], Dir.children(@root)
  end

  private def links(*lines)
    File.write(File.join(@root, "fledge.links"), lines.map { |line| "#{line}\n" }.join)
  end

  private def run_host(abi)
    _, err, status = Open3.capture3(@host, @root, @folder, abi)
    [status.exitstatus, err]
  end

  private def compile
    File.write(File.join(@dir, "main.c"), HOST)
    program = File.join(@dir, "host")
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-I", MOBILE, File.join(@dir, "main.c"),
      File.join(MOBILE, "library_links.c"), "-o", program)
    assert status.success?, err
    program
  end
end
