# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require "rbconfig"

# The mobile embedding API's forwarding of standard output and standard
# error to the system's log (runtime/mobile/output.c; doc/contributors/design/phone-runtimes.md,
# "Output to the system log"), compiled
# with this computer's C compiler beside a log that writes each entry to
# a file, as os_log and logcat would keep it, and run: what a program
# prints must reach the log line by line, standard error's marked as
# errors, with a line longer than an entry holds sent as several entries
# cut between UTF-8 characters.
class MobileOutputTest < Minitest::Test
  MOBILE = File.expand_path("../../runtime/mobile", __dir__)

  # A log for output.c that writes "E " or "O " and each entry to the
  # file the program is given, and a program that forwards its output and
  # then prints: a short line, an empty one, one of 2,500 bytes, one of
  # 999 ASCII bytes and 2-byte characters straddling the cut, one whose
  # cut would end an entry in whitespace, which the unified log trims
  # from an entry's end, a line to standard error, and lines holding NUL
  # bytes, which both logs would cut short at the first, so each goes as
  # the two bytes 0xC0 0x80 as CPython's Android streams write it, or
  # U+2400 on Apple's systems, whose os_log drops an entry of bytes that
  # are no UTF-8, even where that cuts an entry; then it ends with exit()
  # at once, as a windowed app's host does, while the forwarding threads
  # still have lines to write: the log takes 20 milliseconds an entry, so
  # a process that ended without waiting for them would lose the last.
  PROGRAM = <<~C
    #include "fledge_ruby.h"
    #include "mobile.h"
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    static FILE *log_file;

    const char *fledge_ruby_certificates(void) { return NULL; }
    int fledge_log_echoes(void) { return 0; }
    int fledge_log_open(const char *tag) { return strcmp(tag, "org.example.App") == 0 ? 0 : -1; }
    void fledge_log_write(int error, const char *text, size_t length) {
        usleep(20000);
        fprintf(log_file, "%s %.*s\\n", error ? "E" : "O", (int)length, text);
        fflush(log_file);
    }

    int main(int argc, char **argv) {
        (void)argc;
        log_file = fopen(argv[1], "w");
        if (fledge_ruby_forward_output("org.example.App") != 0) return 1;
        char long_line[2501];
        memset(long_line, 'x', 2500);
        long_line[2500] = '\\0';
        char straddling[1100];
        memset(straddling, 'a', 999);
        strcpy(straddling + 999, "\\xC3\\xA9\\xC3\\xA9");
        char spaced[1100];
        memset(spaced, 'b', 998);
        strcpy(spaced + 998, "  \\tc");
        printf("hello\\n\\n%s\\n%s\\n%s\\n", long_line, straddling, spaced);
        fputs("oops\\n", stderr);
        fwrite("p\\0q\\n\\0\\n", 1, 6, stdout);
        char nuls[1100];
        memset(nuls, 'n', 999);
        nuls[999] = '\\0';
        nuls[1000] = '\\0';
        nuls[1001] = '\\n';
        fwrite(nuls, 1, 1002, stdout);
        exit(0);
    }
  C

  def test_forwards_each_line_to_the_log_and_splits_long_ones_between_characters
    skip "the mobile embedding API is for iOS and Android, which share POSIX's pipes; Windows has none" if Gem.win_platform?
    compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{compiler}) on this computer" unless system(compiler, "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "main.c"), PROGRAM)
      program = File.join(dir, "forward")
      _, err, status = Open3.capture3(compiler, "-std=gnu11", "-Wall", "-Werror", "-I", MOBILE, File.join(dir, "main.c"),
        File.join(MOBILE, "output.c"), "-lpthread", "-o", program)
      assert status.success?, err
      log = File.join(dir, "log.txt")

      streams = File.join(dir, "streams")
      assert_predicate finish(Process.spawn(program, log, out: File::NULL, err: File::NULL), seconds: 15), :success?
      null_log = File.read(log, encoding: "UTF-8").lines.sort
      assert_predicate finish(Process.spawn(program, log, out: "#{streams}.out", err: "#{streams}.err"), seconds: 15), :success?
      assert_equal null_log, File.read(log, encoding: "UTF-8").lines.sort, "a tool that holds the streams changed what the log got"
      assert_equal "oops\n", File.read("#{streams}.err", encoding: "UTF-8")
      shown = File.binread("#{streams}.out")
      assert shown.start_with?("hello\n\n#{'x' * 2500}\n"), "the streams a tool holds did not get the app's lines: #{shown[0, 40].inspect}"
      assert shown.end_with?("#{'n' * 999}\0\0\n"), "the streams a tool holds did not get the app's last line: #{shown[-40..].inspect}"

      entries = File.read(log, encoding: "UTF-8").lines.map(&:chomp)
      assert_equal "E oops", entries.find { |entry| entry.start_with?("E ") }
      out = entries.select { |entry| entry.start_with?("O ") }.map { |entry| entry.delete_prefix("O ") }
      nul = RUBY_PLATFORM.include?("darwin") ? "␀" : "\xC0\x80"
      assert_equal [
        "hello",
        "",
        "x" * 1000,
        "x" * 1000,
        "x" * 500,
        "a" * 999,
        "éé",
        "b" * 998,
        "  \tc",
        "p#{nul}q",
        nul,
        "n" * 999,
        nul * 2,
], out
    end
  end

  # A program that forwards its output to Apple's real os_log
  # (apple.c), then prints a line to standard output and one to standard
  # error, waits, and prints one more to standard error, which blocks for
  # ever if the pipe it writes to is full, then waits for the forwarding
  # thread to pass the line on, as an app that runs on does.
  APPLE_PROGRAM = <<~C
    #include "fledge_ruby.h"
    #include <stdio.h>
    #include <unistd.h>

    const char *fledge_ruby_certificates(void) { return NULL; }

    int main(void) {
        if (fledge_ruby_forward_output("org.setdef.fledge.OutputTest") != 0) return 1;
        puts("out");
        fputs("first\\n", stderr);
        sleep(2);
        fputs("last\\n", stderr);
        sleep(1);
        return 0;
    }
  C

  # With OS_ACTIVITY_DT_MODE in the environment, which Xcode and other
  # developer tools set to have the unified log copy each entry to
  # standard error, and which macOS and the iOS Simulator honor whatever
  # its value, even NO, forwarding standard error to os_log
  # would send each entry back into the pipe it came from until the pipe
  # filled and the program blocked. The streams are left as they are
  # instead: each line reaches the tool once, and the program ends.
  # Without it, the lines go to the log and, as the streams are files a
  # tool might read, to them too, once each (devicectl's --console, which
  # sets no such variable, shows an iPhone app's output so). macOS shares
  # iOS's os_log, so this runs on a Mac with the real one.
  def test_leaves_the_streams_alone_when_the_log_copies_itself_to_standard_error
    skip "os_log is Apple's" unless RUBY_PLATFORM.include?("darwin")

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "main.c"), APPLE_PROGRAM)
      program = File.join(dir, "forward")
      _, err, status = Open3.capture3("cc", "-std=gnu11", "-Wall", "-Werror", "-I", MOBILE, File.join(dir, "main.c"),
        File.join(MOBILE, "output.c"), File.join(MOBILE, "apple.c"), "-o", program)
      assert status.success?, err

      ["YES", "NO", ""].each do |value|
        out, err, status = run_for(program, { "OS_ACTIVITY_DT_MODE" => value }, seconds: 20)
        assert_predicate status, :success?, "OS_ACTIVITY_DT_MODE=#{value.inspect}"
        assert_equal ["out\n", "first\nlast\n"], [out, err], "OS_ACTIVITY_DT_MODE=#{value.inspect}"
      end
      out, err, status = run_for(program, { "OS_ACTIVITY_DT_MODE" => nil }, seconds: 20)
      assert_predicate status, :success?
      assert_equal ["out\n", "first\nlast\n"], [out, err], "no OS_ACTIVITY_DT_MODE: the log and the streams both get each line"
    end
  end

  LAUNCHER = File.expand_path("../../runtime/launcher", __dir__)

  # A host, as an app's would be, of the embedding API (fledge_ruby.c)
  # linked with the Ruby running these tests, beside the log of PROGRAM:
  # it forwards its output and runs the Ruby program it is given. This
  # computer's Ruby reads no ruby_embed_libruby_path, which only the
  # mobile runtimes' Ruby has, and may keep ruby_init_ext to itself, so
  # the host defines both, the second weakly, for the linker to prefer
  # Ruby's own where Ruby exports it; it registers no extension, and, as
  # on iOS, links no ruby program.
  RUBY_HOST = <<~C
    #include "fledge_ruby.h"
    #include "mobile.h"
    #include <stdio.h>
    #include <unistd.h>

    const char *ruby_embed_libruby_path;
    __attribute__((weak)) void ruby_init_ext(const char *name, void (*init)(void)) { (void)name; (void)init; }

    static FILE *log_file;

    void fledge_ruby_link_program(const char *root) { (void)root; }
    void fledge_ruby_read_commands(const char *root) { (void)root; }
    int fledge_ruby_load_extensions(const char *caller) { (void)caller; return 0; }
    int fledge_log_echoes(void) { return 0; }
    int fledge_log_open(const char *tag) { (void)tag; return 0; }
    void fledge_log_write(int error, const char *text, size_t length) {
        usleep(100000);
        fprintf(log_file, "%s %.*s\\n", error ? "E" : "O", (int)length, text);
        fflush(log_file);
    }

    int main(int argc, char **argv) {
        (void)argc;
        log_file = fopen(argv[1], "w");
        if (fledge_ruby_forward_output("org.example.App") != 0) return 1;
        return fledge_ruby_run(argv[2], argv[3], 0, NULL);
    }
  C

  # On a phone the log is the only place an app's output goes, so a line
  # an app's Ruby prints must reach it when it is printed, as it reaches
  # a terminal under ruby main.rb, not when the program ends: Ruby
  # buffers its standard output when that is a pipe, as the forwarding
  # makes it, and writes through only on a terminal (io.c,
  # io_binwrite_requires_flush_write, at 4.1.0-preview1). The program
  # prints a line with no flush and then sleeps; the line must be in the
  # log while it sleeps.
  def test_a_line_ruby_prints_reaches_the_log_while_the_program_runs
    skip "the mobile embedding API is for iOS and Android, which share POSIX's pipes; Windows has none" if Gem.win_platform?
    compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{compiler}) on this computer" unless system(compiler, "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      program = compile_ruby_host(compiler, dir)
      script = File.join(dir, "main.rb")
      File.write(script, "puts \"first\"\nsleep 60\n")
      log = File.join(dir, "log.txt")
      errors = File.join(dir, "errors.txt")
      pid = Process.spawn(program, log, dir, script, in: File::NULL, err: errors)
      begin
        deadline = Time.now + 20
        sleep 0.1 until (File.exist?(log) && File.read(log).include?("O first\n")) || Time.now > deadline
        assert_nil Process.wait2(pid, Process::WNOHANG), "the program ended before the line reached the log: #{File.read(errors)}#{File.read(log)}"
        assert_equal "O first\n", File.read(log), "the line did not reach the log within 20 seconds of the start: #{File.read(errors)}#{File.read(log)}"
      ensure
        begin
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end
    end
  end

  # What a program that ends the moment it has printed leaves in the log.
  # The host's log takes 100 milliseconds an entry, so the forwarding
  # thread is still writing the first lines when the program ends, and
  # the process ends with main's return, as a windowed app's does, which
  # ends every thread. Each way a program ends is tried but exit!, which
  # Ruby ends the process with at once (_exit), where no host can wait:
  # falling off its end, exit with a status, an uncaught exception, and
  # an at_exit block that prints.
  ENDINGS = {
    "its end" => ["puts 'one'\n$stderr.puts 'two'\nputs 'last'\n", 0, ["O one", "E two", "O last"]],
    "exit" => ["puts 'one'\nputs 'last'\nexit 3\n", 3, ["O one", "O last"]],
    "an uncaught exception" => ["puts 'one'\nputs 'last'\nraise 'boom'\n", 1, ["O one", "O last"]],
    "at_exit" => ["at_exit { puts 'last' }\nputs 'one'\n", 0, ["O one", "O last"]],
  }.freeze

  def test_a_program_that_ends_at_once_leaves_every_line_in_the_log
    skip "the mobile embedding API is for iOS and Android, which share POSIX's pipes; Windows has none" if Gem.win_platform?
    compiler = RbConfig::CONFIG.fetch("CC").split.first
    skip "no C compiler (#{compiler}) on this computer" unless system(compiler, "--version", out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      program = compile_ruby_host(compiler, dir)
      ENDINGS.each do |ending, (source, status, lines)|
        script = File.join(dir, "main.rb")
        File.write(script, source)
        log = File.join(dir, "log.txt")
        errors = File.join(dir, "errors.txt")
        done = finish(Process.spawn(program, log, dir, script, in: File::NULL, out: File::NULL, err: errors), seconds: 30)
        assert_equal status, done.exitstatus, "a program ending by #{ending}: #{File.read(errors)}"
        entries = File.read(log).lines.map(&:chomp)
        assert_empty lines - entries, "a program ending by #{ending} left the log #{entries.inspect}"
      end
    end
  end

  # Compiles RUBY_HOST in +dir+ with +compiler+, linked with the Ruby
  # running these tests, and returns the program's path.
  # A Ruby with a static libruby loads its extensions as shared objects
  # that find Ruby's symbols in the program that embeds it, so the host
  # is linked with -rdynamic, as the launcher is. It links as Ruby's own
  # ruby does (template/Makefile.in, the $(PROGRAM) rule, at
  # 4.1.0-preview1): Ruby's LDFLAGS first, which name the folders of the
  # libraries its MAINLIBS link, then libruby and those libraries.
  def compile_ruby_host(compiler, dir)
    config = RbConfig::CONFIG
    File.write(File.join(dir, "main.c"), RUBY_HOST)
    FileUtils.mkdir(File.join(dir, "bin"))
    File.symlink(config.fetch("libdir"), File.join(dir, "lib"))
    program = File.join(dir, "bin", "host")
    sources = [
      File.join(dir, "main.c"),
      *%w[fledge_ruby.c output.c].map { |file| File.join(MOBILE, file) },
      *%w[locale.c config.c bundler.c].map { |file| File.join(LAUNCHER, file) },
]
    libraries = "#{config.fetch('LIBRUBYARG')} #{config.fetch('LIBS')} #{config.fetch('MAINLIBS', '')}".split
    _, err, status = Open3.capture3(compiler, "-std=gnu11", "-I", MOBILE, "-I", LAUNCHER, "-I", config.fetch("rubyhdrdir"),
      "-I", config.fetch("rubyarchhdrdir"), *config.fetch("LDFLAGS").split, *sources, "-L", config.fetch("libdir"), *libraries, "-Wl,-rpath,#{config.fetch('libdir')}", "-rdynamic", "-lpthread", "-o", program)
    assert status.success?, err
    program
  end

  # Runs +program+ with +env+, and returns its standard output, its
  # standard error, and its status, failing the test when it has not
  # exited within +seconds+.
  def run_for(program, env, seconds:)
    Dir.mktmpdir do |dir|
      out = File.join(dir, "out")
      err = File.join(dir, "err")
      status = finish(Process.spawn(env, program, out:, err:), seconds:)
      [File.read(out), File.read(err), status]
    end
  end

  # The status of the process +pid+, which fails the test, rather than
  # hanging it, when the process has not exited within +seconds+.
  def finish(pid, seconds:)
    deadline = Time.now + seconds
    until (done = Process.wait2(pid, Process::WNOHANG))
      if Time.now > deadline
        Process.kill("KILL", pid)
        Process.wait(pid)
        flunk "the program did not exit within #{seconds} seconds"
      end
      sleep 0.1
    end
    done.last
  end
end
