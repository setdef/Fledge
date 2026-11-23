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

  def warnings(platform, files)
    entries = files.map { |path, content| Fledge::Entry.file(path, content) }
    Fledge::NativeBuild::Floors.warnings("redcarpet 3.6.1", entries, Fledge::Platform.find(platform), readers: TestReaders.all)
  end

  def test_a_mach_o_file_for_a_newer_macos_than_the_platforms_oldest_is_a_problem
    TestReaders.need(self, :macho)
    found = problems("arm64-darwin", {
      "lib/redcarpet.bundle" => Binaries.macho(minos: "27.0"),
      "lib/old.bundle" => Binaries.macho(minos: "15.0"),
      "lib/redcarpet.rb" => "require 'redcarpet.bundle'\n",
    })

    assert_equal [
      "redcarpet 3.6.1's lib/redcarpet.bundle needs macOS 27.0, and apps for arm64-darwin run on macOS 26.0 and later. " \
        "Compile it with MACOSX_DEPLOYMENT_TARGET=26.0, which Fledge sets, so check its extconf.rb does not override it.",
    ], found
  end

  # A compiled file needs the glibc it was compiled with or a newer one,
  # and the developer's computer may have a newer glibc than the
  # runtime's floor. The app runs wherever that glibc is, so the file is
  # no problem, but the build says what the app now needs, and why, so
  # that the developer can build on an older system.
  def test_an_elf_file_that_needs_a_newer_glibc_than_the_platforms_oldest_is_a_warning_not_a_problem
    TestReaders.need(self, :elf)
    files = {
      "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41]),
      "lib/old.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.34]),
      "lib/plain.so" => Binaries.elf(needed: ["libc.so.6"]),
    }

    assert_empty problems("x86_64-linux", files)
    assert_equal %w[2.41 2.34].map { |version|
      "redcarpet 3.6.1's lib/#{(version == '2.41') ? 'redcarpet' : 'old'}.so needs glibc #{version}, so the app for x86_64-linux " \
        "runs only on Linux with glibc #{version} or newer, where Fledge's runtime runs on glibc 2.28 and later. Fledge compiled " \
        "it on this computer, and a compiled file needs the glibc it was compiled with or a newer one: build the app on a Linux " \
        "with an older glibc, such as AlmaLinux 8, to lower that."
    }, warnings("x86_64-linux", files)
  end

  # An extconf.rb's Makefile installs the extension into the gem's require
  # path, and RubyGems keeps a copy in the extensions folder: the same
  # bytes at two paths, one file to the app (Fledge::CompiledGem), so one
  # warning, not one for each path.
  def test_the_same_file_at_two_paths_is_one_warning
    TestReaders.need(self, :elf)
    elf = Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41])
    files = { "lib/redcarpet.so" => elf, "redcarpet.so" => elf.dup, "lib/other.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.34]) }

    assert_equal ["lib/redcarpet.so", "lib/other.so"], warnings("x86_64-linux", files).map { |warning| warning[/'s (\S+) needs/, 1] }
  end

  # A build that leaves a library for each processor, as a gem for every
  # platform carries one, loads only its own: a file for another
  # processor never loads in the app, so its floor raises nothing.
  def test_an_elf_file_for_another_processor_is_not_judged_by_the_platforms_glibc
    TestReaders.need(self, :elf)
    arm = Binaries.elf(cpu: "aarch64", needed: ["libc.so.6"], versions: %w[GLIBC_2.17 GLIBC_2.41])
    x86 = Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.2.5 GLIBC_2.41])
    files = { "lib/libfoo.aarch64.so" => arm, "lib/libfoo.x86_64.so" => x86 }

    assert_equal ["lib/libfoo.x86_64.so"], warnings("x86_64-linux", files).map { |warning| warning[%r{lib/\S+}] }
    assert_equal ["lib/libfoo.aarch64.so"], warnings("aarch64-linux", files).map { |warning| warning[%r{lib/\S+}] }
  end

  def test_a_mach_o_file_for_another_processor_is_not_judged_by_the_platforms_macos
    TestReaders.need(self, :macho)

    assert_empty problems("arm64-darwin", { "lib/libfoo.x86_64.bundle" => Binaries.macho(cpu: "x86_64", minos: "15.0") })
  end

  # The glibc the app needs is the newest any of its files for its
  # processor needs, and never less than the runtime's floor: a file for
  # another processor never loads in the app, so its glibc is not the
  # app's. A platform without glibc needs none, and an app with no ELF
  # file is read by no tool.
  def test_the_apps_glibc_is_the_newest_its_files_for_its_processor_need
    TestReaders.need(self, :elf)
    files = {
      "lib/newer.so" => Binaries.elf(needed: %w[libc.so.6], versions: %w[GLIBC_2.34]),
      "lib/newest.so" => Binaries.elf(needed: %w[libc.so.6], versions: %w[GLIBC_2.2.5 GLIBC_2.41]),
      "lib/other.so" => Binaries.elf(cpu: "aarch64", needed: %w[libc.so.6], versions: %w[GLIBC_2.17 GLIBC_2.41]),
      "lib/plain.so" => Binaries.elf(needed: %w[libc.so.6]),
      "main.rb" => "puts 1\n",
    }
    glibc = lambda do |chosen, platform = "x86_64-linux", **options|
      entries = files.slice(*chosen).map { |path, content| Fledge::Entry.file(path, content) }
      Fledge::NativeBuild::Floors.glibc(entries, Fledge::Platform.find(platform), readers: TestReaders.all, **options)
    end

    assert_equal "2.41", glibc.call(files.keys)
    assert_equal "2.34", glibc.call(files.keys - ["lib/newest.so"])
    assert_equal "2.28", glibc.call(%w[lib/plain.so lib/other.so])
    assert_equal "2.41", glibc.call(%w[lib/other.so], "aarch64-linux")
    assert_equal "2.39", glibc.call(%w[lib/newer.so], floor: "2.39")
    assert_nil glibc.call(files.keys, "x86_64-linux-musl")
    nothing = Fledge::Binary::Readers.new(commands: {}, install: "no tool")
    assert_equal "2.28", Fledge::NativeBuild::Floors.glibc([Fledge::Entry.file("main.rb", "puts 1\n")], Fledge::Platform.find("x86_64-linux"), readers: nothing)
  end

  def test_a_platform_without_that_floor_judges_no_file_by_it
    assert_empty problems("x86_64-linux", { "lib/redcarpet.bundle" => Binaries.macho(minos: "27.0") })
    assert_empty warnings("x64-mingw-ucrt", { "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.99]) })
    assert_empty problems("arm64-darwin", {
      "lib/redcarpet.so" => Binaries.elf(needed: ["libc.so.6"], versions: %w[GLIBC_2.99]),
      "lib/redcarpet.dll" => Binaries.pe(needed: %w[KERNEL32.dll]),
    })
  end
end
