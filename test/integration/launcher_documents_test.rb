# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "rbconfig"

# The line the macOS launcher prints when Launch Services sends it no
# event (runtime/launcher/documents.c, fledge_documents_give_up_message),
# compiled on its own with a program that asks for it. Whether the wait
# is long enough for a computer under load, where the event comes late,
# is Delivery's: .github/scripts/deliver-windowed.sh opens a document
# with open -a.
class LauncherDocumentsTest < Minitest::Test
  LAUNCHER = File.expand_path("../../runtime/launcher", __dir__)

  PROGRAM = <<~C
    #include "launcher.h"

    #include <stdio.h>

    int main(void) {
        char message[256];
        fledge_documents_give_up_message(message, sizeof message, 15.0, -9875);
        fputs(message, stdout);
        return 0;
    }
  C

  def setup
    skip "only the macOS launcher takes documents" unless RbConfig::CONFIG.fetch("host_os").start_with?("darwin")
  end

  def test_the_launcher_says_how_long_it_waited_and_what_it_found_when_it_gives_up
    Dir.mktmpdir do |dir|
      program = File.join(dir, "message")
      File.write(File.join(dir, "main.c"), PROGRAM)
      compiled = system("clang", "-std=gnu11", "-I", LAUNCHER, File.join(dir, "main.c"), File.join(LAUNCHER, "documents.c"),
        "-framework", "CoreFoundation", "-framework", "CoreServices", "-framework", "Carbon",
        "-o", program, out: File::NULL, err: File::NULL)
      assert compiled, "documents.c and a program that asks for the message did not compile"

      out = IO.popen([program], &:read)

      assert_equal "fledge: Launch Services sent no event in 15 seconds (status -9875), so the program starts without " \
        "the documents it was opened with\n", out
    end
  end
end
