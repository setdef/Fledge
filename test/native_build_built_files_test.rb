# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"

# What ships of a gem's folder after Fledge::NativeBuild built it: what
# RubyGems would leave there that the gem's Ruby may load. A gem's real
# package, and its folder as a build left it, written here; nothing is
# compiled.
class NativeBuildBuiltFilesTest < Minitest::Test
  FILES = {
    "lib/greet.rb" => "require 'ffi'\n",
    "ext/Rakefile" => "task :default\n",
    "ext/aarch64-darwin/libgreet.bundle" => "the author's own build",
    "LICENSE" => "greet is MIT\n",
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @package = Fledge::GemPackage.new(FakeGem.build(@dir, "greet", "1.0.0", files: FILES, extensions: ["ext/Rakefile"]).path)
    @gem_dir = File.join(@dir, "gems", "greet-1.0.0")
    FILES.each { |path, content| write(path, content) }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(@gem_dir, path)))
    File.binwrite(File.join(@gem_dir, path), content)
  end

  def built
    Fledge::NativeBuild::BuiltFiles.of(@package, @gem_dir).to_h { |entry| [entry.path, (entry.type == :symlink) ? "-> #{entry.link}" : entry.content] }
  end

  # ffi-compiler leaves its library in ext/ARCH-OS (scrypt, llhttp-ffi),
  # and rdkafka's Rakefile in ext/, where each gem's Ruby gives ffi_lib
  # its path; neither is in a require path.
  def test_a_library_the_build_left_outside_the_require_paths_ships_at_its_path_without_the_rest_of_the_build
    write("lib/greet/greet.so", "an extension")
    write("ext/x86_64-linux/libgreet.so", "a library for ffi")
    write("ext/x86_64-linux/greet/greet.o", "an object")
    write("ext/Makefile", "all:\n")
    write("ext/librdkafka.so.1", "a versioned library")
    File.symlink("librdkafka.so.1", File.join(@gem_dir, "ext/librdkafka.so"))
    write("ext/greet.bundle.dSYM/Contents/Resources/DWARF/greet.bundle", "debug symbols")
    write("ext/greet.dylib", "a Mac library")
    write("ext/greet.dll", "a Windows library")

    assert_equal({
      "ext/greet.dll" => "a Windows library",
      "ext/greet.dylib" => "a Mac library",
      "ext/librdkafka.so" => "-> librdkafka.so.1",
      "ext/librdkafka.so.1" => "a versioned library",
      "ext/x86_64-linux/libgreet.so" => "a library for ffi",
      "lib/greet/greet.so" => "an extension",
    }, built.sort.to_h)
  end

  # llhttp-ffi 0.5.1 packs a library its author built on a Mac at the
  # path its build writes on Apple silicon: it ships as the package
  # holds it unless the build wrote over it.
  def test_a_library_the_package_holds_ships_from_the_build_only_when_the_build_changed_it
    assert_empty built

    write("ext/aarch64-darwin/libgreet.bundle", "built here")

    assert_equal({ "ext/aarch64-darwin/libgreet.bundle" => "built here" }, built)
  end
end
