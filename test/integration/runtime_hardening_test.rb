# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"
require_relative "../../tasks/runtime_builder"

# RuntimeBuilder::Hardening reads a program this computer's own compiler
# and linker built, with this computer's own objdump, as the runtime
# build does (doc/contributors/design/launcher.md, "Hardening"): a
# program built with the flags Fledge passes has every protection, and
# one built without them lacks the ones its platform lets a compiler
# leave out. Windows' programs are the runtime build's, which
# cross-compiles them; this test needs a Mac or a Linux computer.
class RuntimeHardeningIntegrationTest < Minitest::Test
  PROGRAM = <<~C
    #include <stdio.h>
    #include <string.h>

    int main(int argc, char **argv)
    {
      char copy[32];
      strcpy(copy, argv[0]);
      puts(copy);
      return argc;
    }
  C

  # What each kind's compiler may leave out, and the flags that leave it
  # out, for the program built without hardening.
  UNHARDENED = {
    glibc: %w[-fno-pie -no-pie -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -Wl,-z,norelro,-z,lazy,-z,execstack],
    musl: %w[-fno-pie -no-pie -fno-stack-protector -Wl,-z,norelro,-z,lazy,-z,execstack],
    darwin: %w[-fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0],
  }.freeze

  def setup
    platform = Fledge::Platform.local
    skip "Windows programs are cross-compiled by the runtime build" if platform.windows?
    @kind = if platform.musl? then :musl
    elsif platform.os == "darwin" then :darwin
    else :glibc
    end
    @readers = Fledge::Binary::Readers.local(platform.os)
    @hardening = RuntimeBuilder::Hardening.new(kind: @kind, readers: @readers)
    @cc = ENV.fetch("CC", (@kind == :darwin) ? "clang" : "cc")
  end

  def build(dir, name, flags)
    source = File.join(dir, "program.c")
    File.write(source, PROGRAM)
    program = File.join(dir, name)
    output, status = Open3.capture2e(@cc, "-O2", *flags, source, "-o", program)
    assert_predicate status, :success?, output
    program
  end

  def test_a_program_built_with_the_flags_fledge_passes_has_every_protection
    Dir.mktmpdir do |dir|
      program = build(dir, "hardened", RuntimeBuilder::Hardening::COMPILE.fetch(@kind) + RuntimeBuilder::Hardening::LINK.fetch(@kind))

      assert_empty @hardening.missing(program)
      @hardening.check([program])
    end
  end

  def test_a_program_built_without_them_lacks_what_its_platform_lets_a_compiler_leave_out
    Dir.mktmpdir do |dir|
      program = build(dir, "unhardened", UNHARDENED.fetch(@kind))
      missing = @hardening.missing(program)

      assert_includes missing, "stack protector"
      assert_includes missing, "FORTIFY" unless @kind == :musl
      assert_equal %w[PIE RELRO BIND_NOW non-executable\ stack], missing & %w[PIE RELRO BIND_NOW non-executable\ stack] unless @kind == :darwin
      error = assert_raises(RuntimeError) { @hardening.check([program]) }
      assert_includes error.message, "#{program} lacks "
      assert_includes error.message, "stack protector"
    end
  end
end
