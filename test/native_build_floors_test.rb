# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require_relative "support/binaries"

# What Fledge::NativeBuild says about a compiled file that needs a newer
# system than the oldest its platform's apps run on: a compiler targets
# the computer it runs on unless told otherwise.
class NativeBuildFloorsTest < Minitest::Test
  def problems(platform, files)
    entries = files.map { |path, content| Fledge::Entry.file(path, content) }
    Fledge::NativeBuild::Floors.problems("redcarpet 3.6.1", entries, Fledge::Platform.find(platform))
  end

  def test_a_mach_o_file_for_a_newer_macos_than_the_platforms_oldest_is_a_problem
    found = problems("arm64-darwin", {
      "lib/redcarpet.bundle" => Binaries.macho(minos: "15.0"),
      "lib/old.bundle" => Binaries.macho(minos: "14.0"),
      "lib/redcarpet.rb" => "require 'redcarpet.bundle'\n",
    })

    assert_equal [
      "redcarpet 3.6.1's lib/redcarpet.bundle needs macOS 15.0, and apps for arm64-darwin run on macOS 14.0 and later. " \
        "Compile it with MACOSX_DEPLOYMENT_TARGET=14.0, which Fledge sets, so check its extconf.rb does not override it.",
    ], found
  end

  def test_an_elf_file_that_needs_a_newer_glibc_than_the_platforms_oldest_is_a_problem
    found = problems("x86_64-linux", {
      "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41]),
      "lib/old.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.34]),
    })

    assert_equal [
      "redcarpet 3.6.1's lib/redcarpet.so needs glibc 2.41, and apps for x86_64-linux run on glibc 2.39 and later. " \
        "Build on a Linux with glibc 2.39, such as Ubuntu 24.04.",
    ], found
  end

  def test_a_platform_without_that_floor_judges_no_file_by_it
    assert_empty problems("x86_64-linux", { "lib/redcarpet.bundle" => Binaries.macho(minos: "27.0") })
    assert_empty problems("x64-mingw-ucrt", { "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.99]) })
  end
end
