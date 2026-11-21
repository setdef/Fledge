# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# Which file an Android app's Ruby reads in place of the one it is asked
# for (runtime/mobile/commands.c, fledge_ruby_read_commands;
# doc/contributors/design/phone-runtimes.md, "Gem commands on Android"),
# compiled with this computer's C compiler: RubyGems' wrapper of a gem's
# command, kept in ROOT/libexec/commands, for ROOT/bin/NAME, however the
# path names that folder, and the path itself for every other file Ruby
# loads or requires.
class MobileCommandsTest < Minitest::Test
  MOBILE = File.expand_path("../../runtime/mobile", __dir__)

  # HOST ROOT PATH... sets the commands up for ROOT and prints, for each
  # PATH, the file Ruby would read, or "as asked" for PATH itself, or
  # "no hook" when none was set up.
  HOST = <<~C
    #include "mobile.h"
    #include <stdio.h>

    int (*ruby_embed_source_path)(const char *, char *, size_t);

    int main(int argc, char **argv) {
        char buffer[4096];
        if (argc < 2) return 2;
        fledge_ruby_read_commands(argv[1]);
        for (int index = 2; index < argc; index++) {
            if (ruby_embed_source_path == NULL) puts("no hook");
            else if (ruby_embed_source_path(argv[index], buffer, sizeof buffer)) puts(buffer);
            else puts("as asked");
        }
        return 0;
    }
  C

  def setup
    skip "the Android runtime's commands are POSIX; Windows is not" if Gem.win_platform?
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)

    @dir = File.realpath(Dir.mktmpdir)
    @root = File.join(@dir, "root")
    @commands = File.join(@root, "libexec", "commands")
    FileUtils.mkdir_p([@commands, File.join(@root, "bin"), File.join(@root, "lib", "ruby")])
    File.write(File.join(@dir, "program"), "ELF")
    %w[rake ruby].each { |name| File.symlink(File.join(@dir, "program"), File.join(@root, "bin", name)) }
    File.write(File.join(@commands, "rake"), "# rake's wrapper\n")
    File.write(File.join(@root, "lib", "ruby", "rake"), "# a file named rake elsewhere\n")
    File.write(File.join(@root, "lib", "ruby", "json.rb"), "# a library\n")
    @host = compile
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_a_commands_link_reads_its_wrapper_however_its_folder_is_named
    File.symlink(File.join(@root, "bin"), File.join(@dir, "bin-link"))
    wrapper = File.join(@commands, "rake")

    assert_equal [wrapper] * 3, run_host(File.join(@root, "bin", "rake"), "#{@root}/lib/../bin/rake", File.join(@dir, "bin-link", "rake"))
    assert_equal [wrapper], run_host("rake", chdir: File.join(@root, "bin"))
    assert_equal [wrapper], run_host("../bin/rake", chdir: File.join(@root, "lib"))
  end

  # A file Ruby loads or requires reads as it is: one in another folder,
  # even under a command's name, ruby, which has no wrapper, a name with
  # no wrapper, and a path that does not exist, whose failure to open
  # is Ruby's own.
  def test_every_other_path_reads_as_asked
    paths = [
      File.join(@root, "lib", "ruby", "json.rb"),
      File.join(@root, "lib", "ruby", "rake"),
      File.join(@root, "bin", "ruby"),
      File.join(@root, "bin", "rdoc"),
      File.join(@dir, "nowhere", "rake"),
      "rake",
      "",
]

    assert_equal ["as asked"] * paths.size, run_host(*paths)
  end

  def test_a_ruby_without_wrappers_reads_every_path_as_asked
    FileUtils.rm_rf(File.join(@root, "libexec"))

    assert_equal ["no hook"], run_host(File.join(@root, "bin", "rake"))
  end

  # Runs the host with the root and +paths+ in +chdir+, and returns what
  # it printed for each, failing unless it exited 0.
  private def run_host(*paths, chdir: @dir)
    out, err, status = Open3.capture3(@host, @root, *paths, chdir:)
    assert_predicate status, :success?, err
    out.lines(chomp: true)
  end

  private def compile
    File.write(File.join(@dir, "main.c"), HOST)
    program = File.join(@dir, "host")
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-I", MOBILE, File.join(@dir, "main.c"),
      File.join(MOBILE, "commands.c"), "-o", program)
    assert status.success?, err
    program
  end
end
