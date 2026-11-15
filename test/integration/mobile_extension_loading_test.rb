# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# How the Android runtime opens libfledgeext.so, the library of an app's
# linked extensions, from beside libfledgeruby.so before Ruby boots, so
# that its constructor registers them whether or not the app's host
# loads it by name (runtime/mobile/library_links.c,
# fledge_load_extensions), compiled with this computer's C compiler. The
# library here is one whose constructor says so on standard output.
class MobileExtensionLoadingTest < Minitest::Test
  MOBILE = File.expand_path("../../runtime/mobile", __dir__)

  # The program: HOST MODE FOLDER calls fledge_load_extensions for
  # FOLDER, first opening FOLDER/libfledgeext.so itself when MODE is
  # host-first, as a host that names it in System.loadLibrary does, and
  # exits 0 when it loaded or found none, 1 when it failed.
  HOST = <<~C
    #include "mobile.h"

    #include <dlfcn.h>
    #include <stdio.h>
    #include <string.h>

    int main(int argc, char **argv) {
        char path[4096];

        if (argc != 3) return 2;
        if (strcmp(argv[1], "host-first") == 0) {
            snprintf(path, sizeof path, "%s/libfledgeext.so", argv[2]);
            if (dlopen(path, RTLD_NOW) == NULL) return 3;
        }
        return fledge_load_extensions(argv[2], "fledge_ruby_run") == 0 ? 0 : 1;
    }
  C

  LIBRARY = <<~C
    #include <stdio.h>

    __attribute__((constructor)) static void
    registered(void)
    {
        puts("registered");
        fflush(stdout);
    }
  C

  def setup
    skip "the Android runtime's loading is POSIX; Windows is not" if Gem.win_platform?
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)

    @dir = File.realpath(Dir.mktmpdir)
    @folder = File.join(@dir, "native")
    FileUtils.mkdir_p(@folder)
    @host = compile
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_the_library_beside_the_runtime_is_loaded_and_registers
    library

    assert_equal [0, "registered\n", ""], run_host("alone", @folder)
  end

  # A host that names fledgeext loads the same file first; the runtime's
  # open then finds it loaded, and its constructor runs once.
  def test_a_library_the_host_loaded_first_registers_once
    library

    assert_equal [0, "registered\n", ""], run_host("host-first", @folder)
  end

  def test_an_app_without_the_library_loads_nothing
    assert_equal [0, "", ""], run_host("alone", @folder)
  end

  def test_a_library_that_cannot_load_fails_and_says_why
    File.write(File.join(@folder, "libfledgeext.so"), "not a library\n")

    status, out, err = run_host("alone", @folder)

    assert_equal [1, ""], [status, out]
    assert_match(/\Afledge_ruby_run: could not load the app's extensions: .*libfledgeext\.so/, err)
  end

  # Where the native libraries stay inside the APK there is no folder to
  # look in, and the linker finds the library by its name, as
  # System.loadLibrary does.
  def test_without_a_folder_the_library_is_found_by_its_name
    library

    assert_equal [0, "registered\n", ""], run_host("alone", "", env: { "LD_LIBRARY_PATH" => @folder, "DYLD_LIBRARY_PATH" => @folder })
    assert_equal [0, "", ""], run_host("alone", "")
  end

  private def library
    File.write(File.join(@dir, "library.c"), LIBRARY)
    _, err, status = Open3.capture3(@compiler, "-shared", "-fPIC", File.join(@dir, "library.c"), "-o", File.join(@folder, "libfledgeext.so"))
    assert status.success?, err
  end

  private def run_host(mode, folder, env: {})
    out, err, status = Open3.capture3(env, @host, mode, folder)
    [status.exitstatus, out, err]
  end

  private def compile
    File.write(File.join(@dir, "main.c"), HOST)
    program = File.join(@dir, "host")
    dl = RUBY_PLATFORM.include?("linux") ? ["-ldl"] : []
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-I", MOBILE, File.join(@dir, "main.c"),
      File.join(MOBILE, "library_links.c"), "-o", program, *dl)
    assert status.success?, err
    program
  end
end
