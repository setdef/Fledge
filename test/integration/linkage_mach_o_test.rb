# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require "open3"

# Whether a gem's Mach-O files would load on the Mac an app goes to,
# as dyld searches the run paths of each file on the way to a library
# (Fledge::Linkage; ADR 046): files Xcode's clang links here, as a gem's
# own build would, read with the tools here. test/linkage_test.rb covers
# the rest with files LLVM's linker made.
class LinkageMachOTest < Minitest::Test
  def problems(os, files, provided: [])
    TestReaders.need(self, Fledge::Linkage::FORMATS.fetch(os))
    Fledge::Linkage.new(os:, provided:, readers: TestReaders.all).problems("linked 1.0.0", files)
  end

  # dyld finds an @rpath library only through the run paths of the file
  # that needs it and of the files that loaded that one. A run path into
  # Homebrew's folder reaches nothing the app carries, so a gem whose
  # library sits in a folder no run path names would load only on a Mac
  # with Homebrew.
  def test_an_rpath_library_no_run_path_reaches_keeps_a_gem_from_shipping_on_macos
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: ["/opt/homebrew/lib"])
    end

    assert_equal [
      "linked 1.0.0's lib/ext.bundle needs @rpath/libfoo.dylib, which the gem carries at vendor/libfoo.dylib, but none of the " \
        "run paths dyld would search for it (/opt/homebrew/lib) leads there, so the app could not load it on another computer. " \
        "Give the file a run path that does, such as @loader_path/../vendor (install_name_tool -add_rpath), or build the gem so " \
        "that it has one.",
    ], problems("darwin", files)
  end

  def test_an_rpath_library_with_no_run_path_at_all_says_so
    files = mach_o do |build|
      build.dylib("lib/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["lib/libfoo.dylib"], rpaths: [])
    end

    assert_includes problems("darwin", files).first, "but none of the run paths dyld would search for it (it has none) leads there"
  end

  # A run path outside the app reaches nothing, but costs nothing either
  # when another run path reaches the library: here a framework in a
  # folder beside the bundle, which dyld finds at @loader_path/frameworks.
  def test_a_run_path_that_reaches_the_library_lets_it_ship_beside_one_that_does_not
    files = mach_o do |build|
      build.dylib("lib/frameworks/Foo.framework/Versions/A/Foo", install_name: "@rpath/Foo.framework/Versions/A/Foo")
      build.bundle("lib/ext.bundle", links: ["lib/frameworks/Foo.framework/Versions/A/Foo"],
        rpaths: ["/Library/Frameworks", "@loader_path/frameworks"])
    end

    assert_empty problems("darwin", files)
  end

  # A library a gem's bundle loads finds its own @rpath libraries through
  # the bundle's run paths too, as dyld searches the run paths of every
  # file on the way from the program to it.
  def test_a_library_finds_its_rpath_libraries_through_the_run_paths_of_the_file_that_loaded_it
    files = mach_o do |build|
      build.dylib("vendor/libinner.dylib", install_name: "@rpath/libinner.dylib")
      build.dylib("vendor/libouter.dylib", install_name: "@rpath/libouter.dylib", links: ["vendor/libinner.dylib"])
      build.bundle("lib/ext.bundle", links: ["vendor/libouter.dylib"], rpaths: ["@loader_path/../vendor"])
    end

    assert_empty problems("darwin", files)
  end

  def test_a_loader_path_library_that_is_not_where_it_says_keeps_a_gem_from_shipping
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@loader_path/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: [])
    end

    assert_equal [
      "linked 1.0.0's lib/ext.bundle needs @loader_path/libfoo.dylib, which is not there: the gem carries libfoo.dylib at " \
        "vendor/libfoo.dylib, so the app could not load it on another computer. Build the gem so that the file names the " \
        "library where it is, such as @loader_path/../vendor/libfoo.dylib.",
    ], problems("darwin", files)
  end

  # The runtime's own libraries are where the runtime puts them, which is
  # the runtime's to get right, not the gem's.
  def test_an_rpath_library_the_runtime_ships_is_not_the_gems_to_reach
    files = mach_o do |build|
      build.dylib("build/libruntime.dylib", install_name: "@rpath/libruntime.dylib")
      build.bundle("lib/ext.bundle", links: ["build/libruntime.dylib"], rpaths: [])
    end

    assert_empty problems("darwin", files.except("build/libruntime.dylib"), provided: ["libruntime.dylib"])
  end

  # Where the program sits in the app depends on the app's kind, so a
  # library named from it is judged by its name alone, as before.
  def test_an_executable_path_run_path_is_not_judged
    files = mach_o do |build|
      build.dylib("vendor/libfoo.dylib", install_name: "@rpath/libfoo.dylib")
      build.bundle("lib/ext.bundle", links: ["vendor/libfoo.dylib"], rpaths: ["@executable_path/../lib"])
    end

    assert_empty problems("darwin", files)
  end

  # Builds Mach-O files with Xcode's clang, as a gem's own build would, by
  # their paths in the gem, and returns them with their bytes.
  def mach_o
    skip "builds its Mach-O files with Xcode's clang and install_name_tool, which only a Mac has" unless RUBY_PLATFORM.include?("darwin")
    Dir.mktmpdir("linkage") do |dir|
      build = MachOBuild.new(dir)
      yield build
      build.files
    end
  end

  # A gem's folder of Mach-O files that clang links against each other.
  class MachOBuild
    def initialize(dir)
      @dir = dir
      @paths = []
    end

    # A dynamic library at +path+, whose install name is +install_name+,
    # that links the libraries at +links+.
    def dylib(path, install_name:, links: [])
      link(path, ["-dynamiclib", "-install_name", install_name], links, [])
    end

    # A Ruby-style bundle at +path+ that links +links+ and has the run
    # paths +rpaths+, which install_name_tool adds as a gem's build would.
    def bundle(path, links:, rpaths:)
      link(path, ["-bundle"], links, rpaths)
    end

    def files
      @paths.to_h { |path| [path, File.binread(File.join(@dir, path))] }
    end

    private def link(path, kind, links, rpaths)
      output = File.join(@dir, path)
      FileUtils.mkdir_p(File.dirname(output))
      source = "#{output}.c"
      File.write(source, "void fixture_#{@paths.size}(void) {}\n")
      run("clang", "-arch", "arm64", "-mmacosx-version-min=14.0", "-headerpad_max_install_names", *kind, source, *links.map { |library| File.join(@dir, library) },
        "-o", output)
      File.delete(source)
      rpaths.each { |rpath| run("install_name_tool", "-add_rpath", rpath, output) }
      @paths << path
    end

    private def run(*command)
      output, status = Open3.capture2e(*command)
      raise "#{command.join(' ')} failed:\n#{output}" unless status.success?
    end
  end
end
