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

  # The object file of PROGRAM compiled with +flags+, which is what the
  # recipes read before linking: the linked program holds libruby, which
  # brings a canary and checked calls.
  def object(dir, name, flags)
    source = File.join(dir, "program.c")
    File.write(source, PROGRAM)
    object = File.join(dir, "#{name}.o")
    output, status = Open3.capture2e(@cc, "-O2", *flags, "-c", source, "-o", object)
    assert_predicate status, :success?, output
    object
  end

  # A recipe that compiled +objects+, as its programs' objects.
  def recipe_of(kind, objects)
    recipe = RuntimeBuilder::Recipe.new(builder: nil, build_dir: "")
    recipe.define_singleton_method(:hardening_kind) { kind }
    recipe.define_singleton_method(:objects) { [objects] }
    recipe
  end

  def test_an_object_compiled_with_the_flags_fledge_passes_has_the_canary_and_checked_calls
    Dir.mktmpdir do |dir|
      object = object(dir, "hardened", RuntimeBuilder::Hardening::COMPILE.fetch(@kind))
      recipe_of(@kind, [object]).verify_hardening(dir)
    end
  end

  def test_the_build_refuses_an_object_compiled_without_the_stack_protector
    Dir.mktmpdir do |dir|
      object = object(dir, "no_canary", RuntimeBuilder::Hardening::COMPILE.fetch(@kind) - %w[-fstack-protector-strong] + %w[-fno-stack-protector])
      error = assert_raises(RuntimeError) { recipe_of(@kind, [object]).verify_hardening(dir) }

      assert_includes error.message, "#{object} lacks stack protector"
      refute_includes error.message, "FORTIFY"
    end
  end

  def test_the_build_refuses_an_object_compiled_without_fortify
    skip "musl has no fortified calls" if @kind == :musl
    Dir.mktmpdir do |dir|
      flags = RuntimeBuilder::Hardening::COMPILE.fetch(@kind).grep_v(/FORTIFY/) + %w[-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0]
      object = object(dir, "no_fortify", flags)
      error = assert_raises(RuntimeError) { recipe_of(@kind, [object]).verify_hardening(dir) }

      assert_includes error.message, "#{object} lacks FORTIFY"
      refute_includes error.message, "stack protector"
    end
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
