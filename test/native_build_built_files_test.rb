# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/gems"

# What ships of a gem's folder after Fledge::NativeBuild built it: what
# RubyGems would leave there, and what of it the checks read. A gem's real
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

  # RubyGems leaves a gem's folder as its build left it, less what make
  # clean removes after an extconf.rb's install and the logs
  # Gem::Ext::Builder#build_extension removes, so under bundle exec a
  # gem's Ruby may read any of it by its path: a library ffi-compiler
  # leaves in ext/ARCH-OS (scrypt, llhttp-ffi), or data an extconf.rb
  # writes beside the gem's root.
  def test_everything_the_build_left_in_the_gems_folder_ships_at_its_path
    write("lib/greet/greet.so", "an extension")
    write("ext/x86_64-linux/libgreet.so", "a library for ffi")
    write("ext/x86_64-linux/greet/greet.o", "an object")
    write("ext/Makefile", "all:\n")
    write("data/table.txt", "generated data")
    write("ext/librdkafka.so.1", "a versioned library")
    File.symlink("librdkafka.so.1", File.join(@gem_dir, "ext/librdkafka.so"))
    write("vendor/submodule/.git", "gitdir: ../../.git/modules/submodule\n")

    assert_equal({
      "data/table.txt" => "generated data",
      "ext/Makefile" => "all:\n",
      "ext/librdkafka.so" => "-> librdkafka.so.1",
      "ext/librdkafka.so.1" => "a versioned library",
      "ext/x86_64-linux/greet/greet.o" => "an object",
      "ext/x86_64-linux/libgreet.so" => "a library for ffi",
      "lib/greet/greet.so" => "an extension",
    }, built.sort.to_h)
  end

  # The linkage and floors checks read what Ruby may load of it: every
  # file in the require paths, and each shared library elsewhere, which
  # ffi_lib, Fiddle.dlopen, and require open by path. A program or an
  # object a build tree leaves is never loaded, and a program linked on a
  # newer glibc than the floor needs that glibc's __libc_start_main.
  def test_the_checks_read_the_require_paths_and_the_shared_libraries_of_what_the_build_left
    write("lib/greet/greet.so", "an extension")
    write("lib/greet/table.txt", "data in a require path")
    write("ext/x86_64-linux/libgreet.so", "a library for ffi")
    write("ext/x86_64-linux/greet/greet.o", "an object")
    write("ports/bin/xmllint", "a build tree's program")
    write("ext/librdkafka.so.1", "a versioned library")
    write("ext/greet.bundle.dSYM/Contents/Resources/DWARF/greet.bundle", "debug symbols")
    write("ext/greet.dylib", "a Mac library")
    write("ext/greet.dll", "a Windows library")
    entries = Fledge::NativeBuild::BuiltFiles.of(@package, @gem_dir)

    loaded = Fledge::NativeBuild::BuiltFiles.loaded(entries, @package.spec.require_paths)

    assert_equal [
      "ext/greet.dll",
      "ext/greet.dylib",
      "ext/librdkafka.so.1",
      "ext/x86_64-linux/libgreet.so",
      "lib/greet/greet.so",
      "lib/greet/table.txt",
], loaded.map(&:path).sort
  end

  # A path gem builds in a copy of the files its gemspec lists, with the
  # gemspec evaluated (Fledge::PathPackage#copy_to): of the copy, only
  # what the build wrote is the build's, and the gemspec is Fledge's.
  def test_of_a_path_gems_copy_only_what_its_build_wrote_ships
    source = File.join(@dir, "greeter")
    { "lib/greeter.rb" => "", "ext/greeter/extconf.rb" => "", "LICENSE" => "MIT\n" }.each do |path, content|
      FileUtils.mkdir_p(File.dirname(File.join(source, path)))
      File.write(File.join(source, path), content)
    end
    File.write(File.join(source, "greeter.gemspec"), "Gem::Specification.new { |s| s.name = 'greeter'; s.version = '1.0'; s.summary = 'x'; " \
      "s.authors = ['x']; s.files = ['lib/greeter.rb', 'ext/greeter/extconf.rb', 'LICENSE', 'greeter.gemspec'] }\n")
    package = Fledge::PathPackage.new(Fledge::PathGem.new(name: "greeter", version: "1.0", folder: source, app_path: "vendor/cache/greeter",
      glob: "{,*,*/*}.gemspec", inside: false))
    copy = package.copy_to(File.join(@dir, "copy"))
    FileUtils.mkdir_p(File.join(copy, "data"))
    File.write(File.join(copy, "data/table.txt"), "from the build")

    assert_equal ["data/table.txt"], Fledge::NativeBuild::BuiltFiles.of(package, copy).map(&:path)
  end

  # The compiled gem holds all of it, and the linkage check, which reads
  # its gem files, reads only what Ruby may load.
  def test_a_compiled_gem_holds_what_the_build_left_and_gives_the_linkage_check_what_ruby_loads
    write("ports/bin/xmllint", "a build tree's program")
    write("ext/x86_64-linux/libgreet.so", "a library for ffi")
    compiled = Fledge::CompiledGem.new(package: @package, built: Fledge::NativeBuild::BuiltFiles.of(@package, @gem_dir),
      extensions: [], extension_dir: "extensions/x86_64-linux/4.1.0/greet-1.0.0", build_args: [], build_info: nil, problems: [])

    assert_equal ["a build tree's program", "a library for ffi"], compiled.contents.values_at("ports/bin/xmllint", "ext/x86_64-linux/libgreet.so")
    assert_equal [nil, "a library for ffi"], compiled.gem_files.values_at("ports/bin/xmllint", "ext/x86_64-linux/libgreet.so")
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
