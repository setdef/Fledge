# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"
require "rbconfig"

# The mobile embedding API's forwarding of standard output and standard
# error to the system's log (runtime/mobile/output.c; ADR 011, section 5),
# compiled with this computer's C compiler beside a log that writes each
# entry to a file, as os_log and logcat would keep it, and run: what a
# program prints must reach the log line by line, standard error's marked
# as errors, with a line longer than an entry holds sent as several
# entries cut between UTF-8 characters.
class MobileOutputTest < Minitest::Test
  MOBILE = File.expand_path("../runtime/mobile", __dir__)

  # A log for output.c that writes "E " or "O " and each entry to the
  # file the program is given, and a program that forwards its output and
  # then prints: a short line, an empty one, one of 2,500 bytes, one of
  # 999 ASCII bytes and 2-byte characters straddling the cut, and a line
  # to standard error; then it ends with exit(), which flushes every
  # stdio stream while the forwarding threads wait on their pipes, as an
  # app's would.
  PROGRAM = <<~C
    #include "fledge_ruby.h"
    #include "mobile.h"
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    static FILE *log_file;

    const char *fledge_ruby_certificates(void) { return NULL; }
    int fledge_log_open(const char *tag) { return strcmp(tag, "org.example.App") == 0 ? 0 : -1; }
    void fledge_log_write(int error, const char *text, size_t length) {
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
        printf("hello\\n\\n%s\\n%s\\n", long_line, straddling);
        fputs("oops\\n", stderr);
        fflush(stdout);
        sleep(1);
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

      assert_predicate finish(Process.spawn(program, log), seconds: 15), :success?

      entries = File.read(log, encoding: "UTF-8").lines.map(&:chomp)
      assert_equal "E oops", entries.find { |entry| entry.start_with?("E ") }
      out = entries.select { |entry| entry.start_with?("O ") }.map { |entry| entry.delete_prefix("O ") }
      assert_equal ["hello", "", "x" * 1000, "x" * 1000, "x" * 500, "a" * 999, "éé"], out
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
