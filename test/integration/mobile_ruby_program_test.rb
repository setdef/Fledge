# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# The main function of the Android runtime's ruby program,
# fledge_ruby_main (runtime/mobile/fledge_ruby.c; ADR 082), compiled with
# this computer's C compiler and linked with the Ruby running these
# tests, and run as a Ruby the app starts would be: plain Ruby, as
# Ruby's main.c is, RUBYOPT and all, unless its first argument is the
# app's own program, which runs as the host runs it
# (fledge_ruby_run_app), as the desktop's bin/ruby hands it to the
# app's launcher (ADR 089).
class MobileRubyProgramTest < Minitest::Test
  MOBILE = File.expand_path("../../runtime/mobile", __dir__)
  LAUNCHER = File.expand_path("../../runtime/launcher", __dir__)

  # The program: HOST ROOT ARGV0 ARGS runs fledge_ruby_main with ROOT
  # and ARGV0 ARGS. This computer's Ruby reads no
  # ruby_embed_libruby_path, which only the mobile runtimes' Ruby has,
  # and may keep ruby_init_ext to itself, so the program defines both,
  # the second weakly; it links no program, as android.c would.
  HOST = <<~C
    #include "fledge_ruby.h"
    #include "mobile.h"
    #include <stddef.h>

    const char *ruby_embed_libruby_path;
    __attribute__((weak)) void ruby_init_ext(const char *name, void (*init)(void)) { (void)name; (void)init; }
    void fledge_ruby_link_program(const char *root) { (void)root; }
    int fledge_log_echoes(void) { return 0; }
    int fledge_log_open(const char *tag) { (void)tag; return 0; }
    void fledge_log_write(int error, const char *text, size_t length) { (void)error; (void)text; (void)length; }

    int main(int argc, char **argv) {
        if (argc < 3) return 2;
        return fledge_ruby_main(argv[1], argc - 2, argv + 2);
    }
  C

  # What each script prints: its $0 relative to the root, its ARGV,
  # whether RUBYOPT's -rdate was taken, whether $stdout writes each line
  # as it is printed, rather than buffering it (Ruby warns when
  # IO#syswrite passes buffered bytes), and its sync and tty? as Ruby
  # answers them.
  REPORT = <<~'RUBY'
    root = File.realpath(File.join(__dir__, ".."))
    require "stringio"
    $VERBOSE = false
    warnings, $stderr = $stderr, StringIO.new
    $stdout.write(" ")
    $stdout.syswrite("")
    through = !$stderr.string.include?("buffered IO")
    $stderr = warnings
    print [$0.delete_prefix("#{root}/"), ARGV, defined?(Date) ? "rubyopt" : "no rubyopt", through, $stdout.sync, $stdout.tty?].inspect
  RUBY

  def setup
    skip "the Android runtime's ruby program runs on Android, which is POSIX; Windows is not" if Gem.win_platform?
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)

    @dir = File.realpath(Dir.mktmpdir)
    @root = File.join(@dir, "root")
    FileUtils.mkdir_p(File.join(@root, "app"))
    File.symlink(RbConfig::CONFIG.fetch("libdir"), File.join(@root, "lib"))
    File.write(File.join(@root, "fledge.cfg"), "entry = main.rb\n")
    File.write(File.join(@root, "app", "main.rb"), REPORT)
    File.write(File.join(@root, "app", "other.rb"), REPORT)
    @host = compile
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
  end

  def test_the_apps_program_runs_as_the_host_runs_it
    assert_equal ' ["app/main.rb", ["one", "two"], "no rubyopt", true, false, false]', run_program(File.join(@root, "app", "main.rb"), "one", "two")
  end

  def test_the_apps_program_by_a_relative_path_or_a_link_runs_as_the_host_runs_it
    File.symlink(File.join(@root, "app", "main.rb"), File.join(@dir, "link.rb"))

    assert_equal ' ["app/main.rb", [], "no rubyopt", true, false, false]', run_program("root/app/main.rb", chdir: @dir)
    assert_equal ' ["app/main.rb", [], "no rubyopt", true, false, false]', run_program("link.rb", chdir: @dir)
  end

  def test_another_script_runs_as_plain_ruby
    assert_equal ' ["app/other.rb", ["one"], "rubyopt", false, false, false]', run_program(File.join(@root, "app", "other.rb"), "one")
  end

  def test_an_option_before_the_apps_program_runs_it_as_plain_ruby
    assert_equal ' ["app/main.rb", [], "rubyopt", false, false, false]', run_program("-W0", File.join(@root, "app", "main.rb"))
  end

  def test_ruby_options_run_as_ruby_runs_them
    assert_equal "2 rubyopt", run_program("-e", 'print 1 + 1, " ", defined?(Date) ? "rubyopt" : "no rubyopt"')
  end

  def test_without_a_fledge_cfg_the_apps_program_runs_as_plain_ruby
    File.delete(File.join(@root, "fledge.cfg"))

    assert_equal ' ["app/main.rb", [], "rubyopt", false, false, false]', run_program(File.join(@root, "app", "main.rb"))
  end

  # The runtime's CA certificates are found as rv-ruby's Ruby finds its
  # own, by openssl.rb as openssl loads (RuntimeBuilder::Certificates),
  # so an app's ENV holds nothing the system did not give it: neither the
  # app's program nor a Ruby it starts sees an SSL_CERT_FILE of the
  # runtime's.
  def test_the_runtimes_certificates_add_nothing_to_env
    FileUtils.mkdir_p(File.join(@root, "libexec"))
    File.write(File.join(@root, "libexec", "cert.pem"), "")
    File.write(File.join(@root, "app", "main.rb"), 'print ENV.fetch("SSL_CERT_FILE", "unset")')
    unset = { "SSL_CERT_FILE" => nil }

    assert_equal "unset", run_program(File.join(@root, "app", "main.rb"), env: unset)
    assert_equal "unset", run_program("-e", 'print ENV.fetch("SSL_CERT_FILE", "unset")', env: unset)
  end

  # Runs the program as ruby ARGS, with RUBYOPT=-rdate and +env+, and
  # standard output a pipe, and returns what it printed, failing unless
  # it exited 0.
  private def run_program(*, chdir: @dir, env: {})
    out, err, status = Open3.capture3({ "RUBYOPT" => "-rdate" }.merge(env), @host, @root, "ruby", *, chdir:)
    assert_predicate status, :success?, err
    out
  end

  # Compiles HOST with the embedding API, linked with the Ruby running
  # these tests, with -rdynamic, as the launcher is, for a Ruby with a
  # static libruby whose extensions find its symbols in the program, and
  # Ruby's LDFLAGS first, which name the folders of the libraries its
  # MAINLIBS link, as Ruby's own ruby is linked. It is ROOT/bin/ruby,
  # as RbConfig.ruby names the program in an app: a Ruby built with
  # --enable-load-relative and a static libruby, as jdx/ruby's are,
  # takes its prefix from the program that holds libruby, the parent of
  # its bin folder (ruby.c, ruby_init_loadpath, lines 712 to 722 at
  # 4.1.0-preview1), and finds its library in ROOT/lib, this Ruby's.
  private def compile
    config = RbConfig::CONFIG
    File.write(File.join(@dir, "main.c"), HOST)
    FileUtils.mkdir_p(File.join(@root, "bin"))
    program = File.join(@root, "bin", "ruby")
    sources = [
      File.join(@dir, "main.c"),
      File.join(MOBILE, "fledge_ruby.c"),
      *%w[locale.c config.c bundler.c].map { |file| File.join(LAUNCHER, file) },
    ]
    libraries = "#{config.fetch('LIBRUBYARG')} #{config.fetch('LIBS')} #{config.fetch('MAINLIBS', '')}".split
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-I", MOBILE, "-I", LAUNCHER, "-I", config.fetch("rubyhdrdir"),
      "-I", config.fetch("rubyarchhdrdir"), *config.fetch("LDFLAGS").split, *sources, "-L", config.fetch("libdir"), *libraries, "-Wl,-rpath,#{config.fetch('libdir')}",
      "-rdynamic", "-lpthread", "-o", program)
    assert status.success?, err
    program
  end
end
