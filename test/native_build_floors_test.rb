# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"

# What Fledge::NativeBuild says about a compiled file that needs a newer
# system than the oldest its platform's apps run on: a compiler targets
# the computer it runs on unless told otherwise.
class NativeBuildFloorsTest < Minitest::Test
  def problems(platform, files)
    entries = files.map { |path, content| Fledge::Entry.file(path, content) }
    Fledge::NativeBuild::Floors.problems("redcarpet 3.6.1", entries, Fledge::Platform.find(platform), readers: TestReaders.all)
  end

  def test_a_mach_o_file_for_a_newer_macos_than_the_platforms_oldest_is_a_problem
    TestReaders.need(self, :macho)
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
    TestReaders.need(self, :elf)
    found = problems("x86_64-linux", {
      "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41]),
      "lib/old.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.34]),
    })

    assert_equal [
      "redcarpet 3.6.1's lib/redcarpet.so needs glibc 2.41, and apps for x86_64-linux run on glibc 2.39 and later. " \
        "Build on a Linux with glibc 2.39, such as Ubuntu 24.04.",
    ], found
  end

  # A build that leaves a library for each processor, as a gem for every
  # platform carries one, loads only its own: a file for another
  # processor never loads in the app, so its floor is no problem.
  def test_an_elf_file_for_another_processor_is_not_judged_by_the_platforms_glibc
    TestReaders.need(self, :elf)
    arm = Binaries.elf(cpu: "aarch64", needed: ["libc.so.6"], versions: %w[GLIBC_2.17 GLIBC_2.41])
    x86 = Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41])
    files = { "lib/libfoo.aarch64.so" => arm, "lib/libfoo.x86_64.so" => x86 }

    assert_equal ["lib/libfoo.x86_64.so"], problems("x86_64-linux", files).map { |problem| problem[%r{lib/\S+}] }
    assert_equal ["lib/libfoo.aarch64.so"], problems("aarch64-linux", files).map { |problem| problem[%r{lib/\S+}] }
  end

  def test_a_mach_o_file_for_another_processor_is_not_judged_by_the_platforms_macos
    TestReaders.need(self, :macho)

    assert_empty problems("arm64-darwin", { "lib/libfoo.x86_64.bundle" => Binaries.macho(cpu: "x86_64", minos: "15.0") })
  end

  def test_a_platform_without_that_floor_judges_no_file_by_it
    assert_empty problems("x86_64-linux", { "lib/redcarpet.bundle" => Binaries.macho(minos: "27.0") })
    assert_empty problems("x64-mingw-ucrt", { "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.99]) })
    assert_empty problems("arm64-darwin", {
      "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.99]),
      "lib/redcarpet.dll" => Binaries.pe(needed: %w[KERNEL32.dll]),
    })
  end
end
