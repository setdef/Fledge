# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require "rbconfig"
require_relative "test_helper"
require_relative "../tasks/runtime_builder"

# A phone's runtime links every bundled gem's extension into one library
# beside libruby, and prism's extension compiles its own libprism, which
# libruby holds too, from other sources (ADR 067). Each gem's extension
# keeps every symbol but its Init function to itself: here a fake prism,
# built by this computer's mkmf and compiler with the depend file
# BundledExtensions writes and this system's tools for the recipe the
# phone of the same system uses, is linked into a program that has its
# own pm_parse, as libruby has.
class BundledExtensionsTest < Minitest::Test
  # The extension, compiled with -fvisibility=hidden as prism's
  # extconf.rb and the iOS runtime compile it, and with -fcommon, as
  # Xcode's clang compiles for iOS: pm_parse and pm_state, a global
  # without an initializer, in one file, and in another Init_prism,
  # hidden as an Init function is that nothing exports, which calls it,
  # and pm_version, which nothing hides.
  PARSER = "int pm_state;\nint pm_parse(int source) { return source + 1 + pm_state; }\n"
  INIT = "int pm_parse(int source);\nint Init_prism(void) { return pm_parse(41); }\n" \
    "__attribute__((visibility(\"default\"))) int pm_version(void) { return 1; }\n"

  # The program: libruby's own pm_parse, pm_state, and pm_version, and a
  # call to the extension's Init function.
  PROGRAM = "#include <stdio.h>\nint Init_prism(void);\nint pm_state = 100;\nint pm_parse(int source) { return -source; }\n" \
    "int pm_version(void) { return 2; }\n" \
    "int main(void) { printf(\"%d %d %d\\n\", Init_prism(), pm_parse(1), pm_version()); return 0; }\n"

  def setup
    skip "the phones' runtimes are built on macOS and Linux" if Gem.win_platform?
  end

  def test_an_extension_keeps_its_symbols_beside_a_library_with_the_same_names
    Dir.mktmpdir do |dir|
      archive = build_extension(dir)

      program = File.join(dir, "program")
      File.write("#{program}.c", PROGRAM)
      sh(*RbConfig::CONFIG["CC"].split, "-o", program, "#{program}.c", archive, chdir: dir)
      assert_equal "42 -1 2\n", sh(program, chdir: dir)
    end
  end

  def test_the_extensions_library_holds_one_object_with_only_its_init_global
    Dir.mktmpdir do |dir|
      archive = build_extension(dir)

      assert_equal ["prism-relocatable.o"], sh("ar", "t", archive, chdir: dir).lines.map(&:strip).reject { |name| name.start_with?("__.SYMDEF") }
      globals = sh("nm", "-g", "-P", archive, chdir: dir).lines.filter_map do |line|
        name, type = line.split
        next unless type

        name.delete_prefix("_") if type.match?(/\A[A-TV-Z]\z/)
      end
      assert_equal ["Init_prism"], globals
    end
  end

  # The recipe of the phone built on this system: Apple's, as
  # IOS#relocatable has it, or the NDK's, as Android#relocatable has it,
  # with GNU's objcopy for the NDK's llvm-objcopy.
  def recipe
    if RUBY_PLATFORM.include?("darwin")
      ["$(CC) -r -nostdlib -Wl,-keep_private_externs -o $@ $(FLEDGE_OBJS)", "echo _$(FLEDGE_INIT) > $@.keep", "nmedit -s $@.keep $@"]
    else
      ["$(CC) -r -nostdlib -o $@ $(FLEDGE_OBJS)", "objcopy --keep-global-symbol=$(FLEDGE_INIT) $@"]
    end
  end

  # Builds the fake prism's static library with mkmf, as extmk builds a
  # gem's extension linked into Ruby, and returns its path.
  def build_extension(dir)
    ext = File.join(dir, "ext")
    FileUtils.mkdir_p(ext)
    File.write(File.join(ext, "extconf.rb"), "x")
    File.write(File.join(ext, "parser.c"), PARSER)
    File.write(File.join(ext, "init.c"), INIT)
    RuntimeBuilder::BundledExtensions.relocate(dir, recipe:)
    sh(RbConfig.ruby, "-rmkmf", "-e", '$static = true; append_cflags(%w[-fvisibility=hidden -fcommon]); create_makefile("prism")', chdir: ext)
    sh("make", "prism.#{RbConfig::CONFIG['LIBEXT']}", chdir: ext)
    File.join(ext, "prism.#{RbConfig::CONFIG['LIBEXT']}")
  end

  def sh(*command, chdir:)
    out, status = Open3.capture2e(*command, chdir:)
    assert status.success?, "#{command.join(' ')} failed:\n#{out}"
    out
  end
end
