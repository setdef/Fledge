# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# The macOS and Linux launcher (runtime/launcher/unix.c), compiled with
# the Ruby running these tests, and started with an environment that
# execve(2) passes as it is given. That Ruby is built load-relative, as
# a runtime's is, so the launcher finds its standard library through a
# lib beside it that links to that Ruby's own.
class LauncherEnvironmentTest < Minitest::Test
  LAUNCHER = File.expand_path("../../runtime/launcher", __dir__)

  # Runs argv[1] with the environment argv[2..], exactly, whatever its
  # entries are: Ruby's own spawn writes every entry as NAME=value.
  WITH_ENVIRONMENT = <<~C
    #include <stdio.h>
    #include <unistd.h>

    int main(int argc, char **argv) {
        char *arguments[] = {argv[1], NULL};
        (void)argc;
        execve(argv[1], arguments, argv + 2);
        perror("execve");
        return 127;
    }
  C

  def setup
    skip "the Windows launcher reads its environment from Windows, not environ" if Gem.win_platform?
    @compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{@compiler}) on this computer" unless system(@compiler, "--version", out: File::NULL, err: File::NULL)
  end

  # An environment entry need not hold "=": execve takes any string, and
  # getenv, unsetenv, and Ruby's ENV (hash.c, env_each_pair) all pass one
  # by as no variable. A launcher that tried to remove "RUBYOPT" as a
  # variable never could, and scanned the environment again for ever; it
  # must leave such an entry to the app, which sees no variable in it, as
  # under ruby main.rb.
  def test_an_entry_with_no_equals_sign_is_left_alone
    Dir.mktmpdir do |dir|
      program = compile_app(dir, "puts ENV.key?('RUBYOPT').inspect\n")
      with_environment = compile(dir, "with_env", WITH_ENVIRONMENT)

      out, err, status = run_for(with_environment, program, "HOME=#{dir}", "RUBYOPT", seconds: 30)

      assert_equal ["false\n", "", 0], [out, err, status.exitstatus]
    end
  end

  # +source+ compiled as a program called +name+ in +dir+, with +sources+
  # and +flags+ beside it.
  def compile(dir, name, source, sources = [], flags = [])
    File.write(File.join(dir, "#{name}.c"), source)
    program = File.join(dir, name)
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-Wall", "-Werror", File.join(dir, "#{name}.c"), *sources,
      *flags, "-o", program)
    assert status.success?, err
    program
  end

  # A built app's folder in +dir+/App, whose program runs +main+: the
  # launcher, its fledge.cfg, its app/main.rb, and its Ruby's lib. The
  # program links as Ruby's own ruby does (template/Makefile.in, the
  # $(PROGRAM) rule, at 4.1.0-preview1): Ruby's LDFLAGS first, which
  # name the folders of the libraries its MAINLIBS link, then libruby
  # and those libraries.
  def compile_app(dir, main)
    config = RbConfig::CONFIG
    root = File.join(dir, "App")
    FileUtils.mkdir_p(File.join(root, "app"))
    File.symlink(config.fetch("libdir"), File.join(root, "lib"))
    File.write(File.join(root, "fledge.cfg"), "entry = main.rb\n")
    File.write(File.join(root, "app", "main.rb"), main)
    os_file = RUBY_PLATFORM.include?("darwin") ? "darwin.c" : "linux.c"
    sources = %w[unix.c scrub.c config.c bundler.c locale.c].map { |file| File.join(LAUNCHER, file) } << File.join(LAUNCHER, os_file)
    program = File.join(root, "Probe")
    libraries = "#{config.fetch('LIBRUBYARG')} #{config.fetch('LIBS')} #{config.fetch('MAINLIBS', '')}".split
    _, err, status = Open3.capture3(@compiler, "-std=gnu11", "-I", LAUNCHER, "-isystem", config.fetch("rubyhdrdir"),
      "-isystem", config.fetch("rubyarchhdrdir"), *config.fetch("LDFLAGS").split, *sources, "-L", config.fetch("libdir"), *libraries,
      "-Wl,-rpath,#{config.fetch('libdir')}", "-rdynamic", "-lpthread", "-o", program)
    assert status.success?, err
    program
  end

  # Runs +program+ with +arguments+, and returns its standard output, its
  # standard error, and its status, failing the test when it has not
  # exited within +seconds+.
  def run_for(program, *, seconds:)
    Dir.mktmpdir do |dir|
      out = File.join(dir, "out")
      err = File.join(dir, "err")
      pid = Process.spawn(program, *, out:, err:, in: File::NULL)
      deadline = Time.now + seconds
      until (done = Process.wait2(pid, Process::WNOHANG))
        if Time.now > deadline
          Process.kill("KILL", pid)
          Process.wait(pid)
          flunk "the program did not exit within #{seconds} seconds: #{File.read(err)}"
        end
        sleep 0.1
      end
      [File.read(out), File.read(err), done.last]
    end
  end
end
