# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# What Fledge::NativeBuild says about a gem whose gemspec lists
# extensions and whose build left no file Ruby loads: ruby2d's
# extconf.rb writes an empty Makefile and exits 0 when its libraries are
# missing, so RubyGems installs the gem without its extension.
class NativeBuildSkippedTest < Minitest::Test
  def warnings(extensions, paths)
    entries = paths.map { |path| Fledge::Entry.file(path, "x") }
    Fledge::NativeBuild::Skipped.warnings("ruby2d 1.0.0", extensions, entries)
  end

  def test_a_gem_with_extensions_and_no_shared_library_is_a_warning_naming_the_gem
    found = warnings(["ext/ruby2d/extconf.rb"], ["lib/ruby2d.rb", "ext/ruby2d/Makefile"])

    assert_equal 1, found.size
    assert_includes found.first, "ruby2d 1.0.0"
    assert_includes found.first, "ext/ruby2d/extconf.rb"
  end

  def test_a_gem_whose_build_left_a_library_is_no_warning
    assert_empty warnings(["ext/x/extconf.rb"], ["lib/x/x.so"])
    assert_empty warnings(["ext/x/extconf.rb"], ["lib/x/x.bundle"])
    assert_empty warnings(["ext/x/extconf.rb"], ["ext/x86_64-linux/libx.so.1"])
  end

  def test_debug_symbols_are_not_a_library
    refute_empty warnings(["ext/x/extconf.rb"], ["lib/x.bundle.dSYM/Contents/Resources/DWARF/x.bundle"])
  end

  def test_a_gem_with_no_extensions_is_no_warning
    assert_empty warnings([], ["lib/x.rb"])
  end
end
