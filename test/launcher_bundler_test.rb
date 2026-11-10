# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# How the launcher learns which Bundler an app runs (ADR 063): fledge.cfg's
# bundler key, read by runtime/launcher/config.c, and the Ruby that
# runtime/launcher/bundler.c writes to load that Bundler and have it set
# up the app's gems, compiled with this computer's C compiler and run by
# the Ruby running these tests.
class LauncherBundlerTest < Minitest::Test
  LAUNCHER = File.expand_path("../runtime/launcher", __dir__)

  # Prints what fledge.cfg, given as argv[1], names as the Bundler, or why
  # it is refused; or with argv[1] "code", the Ruby that requires Bundler
  # argv[2] (or the runtime's, for "-") and the Ruby that sets it up.
  DRIVER = <<~C
    #include "launcher.h"

    #include <stdio.h>
    #include <string.h>

    int main(int argc, char **argv) {
        (void)argc;
        if (strcmp(argv[1], "code") == 0) {
            char require[512];
            char setup[512];
            const char *version = strcmp(argv[2], "-") == 0 ? NULL : argv[2];
            if (fledge_bundler_code(require, sizeof require, version, 0) != 0) return 2;
            if (fledge_bundler_code(setup, sizeof setup, version, 1) != 0) return 2;
            printf("%s\\n--\\n%s", require, setup);
            return 0;
        }
        struct fledge_config config;
        const char *problem = "";
        if (fledge_parse_config(argv[1], NULL, fledge_same_ascii_name, &config, &problem) != 0) {
            printf("refused: %s\\n", problem);
            return 1;
        }
        printf("bundler: %s\\n", config.bundler == NULL ? "(none)" : config.bundler);
        return 0;
    }
  C

  def setup
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)
    @dir = File.realpath(Dir.mktmpdir)
    File.write(File.join(@dir, "driver.c"), DRIVER)
    @driver = File.join(@dir, "driver")
    sources = %w[config.c bundler.c].map { |file| File.join(LAUNCHER, file) }
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-I", LAUNCHER, File.join(@dir, "driver.c"),
      *sources, "-o", @driver)
    assert status.success?, err
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def driver(*)
    out, status = Open3.capture2(@driver, *)
    [out, status.exitstatus]
  end

  def test_fledge_cfg_names_the_bundler_beside_the_gemfile
    assert_equal ["bundler: 4.0.19\n", 0], driver("entry = main.rb\ngemfile = Gemfile\nbundler = 4.0.19\n")
    assert_equal ["bundler: 4.1.0.beta2\n", 0], driver("entry = main.rb\ngemfile = Gemfile\nbundler = 4.1.0.beta2\n")
    assert_equal ["bundler: (none)\n", 0], driver("entry = main.rb\ngemfile = Gemfile\n")
  end

  # The version becomes part of a path and of Ruby code, so fledge.cfg may
  # name only what a gem's version holds; and the Bundler, like the
  # Gemfile, is the whole app's.
  def test_a_bundler_that_is_no_version_or_inside_a_section_is_refused
    ["../../evil", "4.0.19'); system('id", "", "4.0.19 4.0.20"].each do |version|
      assert_equal ["refused: names a Bundler that is not a version\n", 1], driver("entry = main.rb\nbundler = #{version}\n"), version
    end
    assert_equal ["refused: names bundler inside a program's section\n", 1], driver("gemfile = Gemfile\n[App]\nentry = main.rb\nbundler = 4.0.19\n")
    assert_equal ["refused: names the same key twice\n", 1], driver("entry = main.rb\nbundler = 4.0.19\nbundler = 4.0.19\n")
  end

  # The runtime's own Bundler loads from Ruby's library, as before. The
  # one fledge.cfg names loads from its gem's lib, which goes first on the
  # load path, where bundle exec's RUBYLIB puts it for the program it runs
  # (Bundler::SharedHelpers#set_rubylib, at Bundler 4.0.20), and its
  # bundler/setup, by path, as bundle exec's RUBYOPT requires it.
  def test_the_ruby_that_loads_the_named_bundler_loads_it_from_its_gem
    gems = File.join(@dir, "gems")
    lib = File.join(gems, "gems", "bundler-9.9.9", "lib")
    FileUtils.mkdir_p(File.join(lib, "bundler"))
    File.write(File.join(lib, "bundler.rb"), "$loaded << :bundler\n")
    File.write(File.join(lib, "bundler", "setup.rb"), "$loaded << :setup\n")
    code, status = driver("code", "9.9.9")
    assert_equal 0, status
    require_bundler, setup = code.split("\n--\n")

    script = "$loaded = []\nGem.paths = { 'GEM_HOME' => ARGV[0] }\n#{require_bundler}\n#{setup}\n" \
      "p $loaded, $LOAD_PATH.first, $LOADED_FEATURES.grep(/bundler-9/).map { File.basename(_1) }"
    out, err, ruby_status = Open3.capture3(RbConfig.ruby, "-e", script, gems)
    assert ruby_status.success?, err
    assert_equal "[:bundler, :setup]\n#{lib.inspect}\n[\"bundler.rb\", \"setup.rb\"]\n", out

    runtime, = driver("code", "-")
    assert_equal "require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler')\n--\nbegin\n" \
      "  require File.join(RbConfig::CONFIG['rubylibdir'], 'bundler/setup')\nrescue StandardError => e\n  $stderr.puts(e.message)\n" \
      "  raise\nend\n", runtime
  end
end
