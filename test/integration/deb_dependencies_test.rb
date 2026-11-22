# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/deb"
require_relative "../support/binaries"
require "open3"

# The dependencies of a .deb Fledge::Deb writes, as
# dpkg-shlibdeps finds them for a gem's extension this computer's cc
# compiles. test/deb_test.rb covers the rest of the package.
class DebDependenciesTest < Minitest::Test
  include DebHelpers

  # The platform of this computer's processor, whose files cc compiles,
  # so that a check of the package's processor judges them.
  HOST = (RbConfig::CONFIG["host_cpu"] == "aarch64") ? ARM : X86

  # A gem's extension, compiled here, that needs zlib from the
  # distribution, as a wrapper of a desktop library needs that library.
  # Every Debian and Ubuntu has zlib1g; only its library is needed, not
  # its headers.
  def zlib_extension(dir)
    shlibdeps = system("dpkg-shlibdeps", "--version", out: File::NULL, err: File::NULL)
    compiler = system("cc", "--version", out: File::NULL, err: File::NULL)
    unless shlibdeps && compiler
      message = "a .deb depends on what dpkg-shlibdeps, from Debian's dpkg-dev, finds, here for a file cc compiles"
      ENV["FLEDGE_REQUIRE_DPKG_DEB"] ? flunk(message) : skip(message)
    end
    path = File.join(dir, "wrapper.so")
    source = "const char *zlibVersion(void);\nconst char *wrapper_version(void) { return zlibVersion(); }\n"
    out, status = Open3.capture2e("cc", "-shared", "-fPIC", "-x", "c", "-", "-o", path, "-l:libz.so.1", stdin_data: source)
    assert_predicate status, :success?, out
    path
  end

  # A library fledge.yml lists as the distribution's becomes a
  # dependency on the package that provides it, as dpkg-shlibdeps finds
  # it for the files that need it, beside glibc's, which stays the
  # runtime's. With nothing listed, glibc's stays the only one, whatever
  # the gems' files need.
  def test_a_library_listed_as_the_distributions_is_a_dependency_on_its_package
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      extension = zlib_extension(dir)
      depends = field(build(File.join(dir, "listed").tap { |d| FileUtils.mkdir_p(d) }, platform: HOST, extension:, system_libraries: ["libz.so.1"]), "Depends")
      plain = field(build(File.join(dir, "plain").tap { |d| FileUtils.mkdir_p(d) }, platform: HOST, extension:), "Depends")

      assert_match(/\Alibc6 \(>= 2\.28\), zlib1g \(>= [^)]+\)\z/, depends)
      assert_equal "libc6 (>= 2.28)", plain
    end
  end

  # A gem's extension compiled on a Linux whose glibc is newer than the
  # runtime's floor needs that glibc where it calls a function glibc
  # added since, here arc4random, from glibc 2.36: the package depends
  # on the glibc the file needs, so apt refuses an older system.
  def test_a_file_compiled_against_a_newer_glibc_raises_the_packages_glibc
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      zlib_extension(dir) # needs cc, as the other tests here do
      path = File.join(dir, "random.so")
      source = "#include <stdlib.h>\nunsigned int random_number(void) { return arc4random(); }\n"
      out, status = Open3.capture2e("cc", "-shared", "-fPIC", "-x", "c", "-", "-o", path, stdin_data: source)
      skip "this computer's glibc has no arc4random, which glibc 2.36 added:\n#{out}" unless status.success?
      needs = Fledge::Binary.read([path], readers: Fledge::Binary::Readers.local("linux")).fetch(path).glibc_minimum.to_s
      assert_operator Gem::Version.new(needs), :>=, Gem::Version.new("2.36"), "the premise: the file needs a glibc newer than the floor"

      assert_equal "libc6 (>= #{needs})", field(build(dir, platform: HOST, extension: path), "Depends")
    end
  end

  # A gem for every platform carries a library for each processor, and
  # the one for another than the app's needs the listed library too. The
  # app never loads it, so dpkg-shlibdeps, which would look for that
  # processor's package of the library, is not asked about it: the
  # dependencies are those of the app's own processor's files.
  def test_a_file_for_another_processor_adds_no_dependency
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      extension = zlib_extension(dir)
      other = (HOST == ARM) ? Binaries.elf(needed: %w[libz.so.1 libstdc++.so.6 ld-linux-x86-64.so.2]) : Binaries.elf(cpu: "aarch64", needed: %w[libz.so.1 libc.so.6])
      depends = field(build(dir, platform: HOST, extension:, files: { "libwrapper.other.so" => other }, system_libraries: ["libz.so.1"]), "Depends")

      assert_match(/\Alibc6 \(>= 2\.28\), zlib1g \(>= [^)]+\)\z/, depends)
    end
  end

  # Such a gem carries its macOS and Windows libraries too, as
  # raylib-bindings carries lib/libraylib.arm64.dylib and
  # lib/libraylib.dll beside its .so files. Linux loads neither, and a
  # Linux computer's objdump may read no Mach-O file, so the .deb reads
  # only its ELF files.
  def test_a_file_for_another_system_adds_no_dependency
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      extension = zlib_extension(dir)
      others = { "libwrapper.arm64.dylib" => Binaries.macho, "wrapper.dll" => Binaries.pe(needed: %w[KERNEL32.dll]) }
      depends = field(build(dir, platform: HOST, extension:, files: others, system_libraries: ["libz.so.1"]), "Depends")

      assert_match(/\Alibc6 \(>= 2\.28\), zlib1g \(>= [^)]+\)\z/, depends)
    end
  end
end
