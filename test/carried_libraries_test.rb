# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/binaries"

# What a macOS app carries from the developer's computer when its
# project lists libraries under macos: carried_libraries
# (Fledge::CarriedLibraries): which files it finds where dyld would, what
# it refuses, and which of the needs of the gems' files and of the copies
# it changes. The files are the test catalog's (test/support/binaries.rb),
# placed in a folder that stands in for this computer's root, so that a
# path such as /opt/homebrew/opt/libxml2/lib names a file the test wrote.
# test/integration/carried_libraries_test.rb rewrites real files with
# install_name_tool and runs the app.
class CarriedLibrariesTest < Minitest::Test
  LIBXML2 = "/opt/homebrew/opt/libxml2/lib/libxml2.2.dylib"

  def setup
    TestReaders.need(self, :macho)
    @root = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@root) if @root
  end

  # A gem's extension, as nokogiri's built against Homebrew's libxml2
  # names it: by its absolute path, beside a library of the gem's own and
  # two of the system's.
  def gem_file
    Binaries.macho(needed: [
      "/usr/lib/libSystem.B.dylib",
      "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation",
      "@loader_path/../ports/libpq.5.dylib",
      LIBXML2,
    ])
  end

  # Writes +content+ at +path+ on the stand-in computer.
  def place(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.binwrite(full, content)
  end

  def carried(names, files)
    Fledge::CarriedLibraries.new(names, files:, platform: Fledge::Platform.find("arm64-darwin"), readers: TestReaders.all, root: @root)
  end

  def test_a_listed_library_is_copied_and_each_file_that_needs_it_is_pointed_at_the_copy
    place(LIBXML2, Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib]))
    plan = carried(["libxml2.2.dylib"], {
      "lib/ruby/gems/4.1.0/gems/xml-1.0/lib/xml.bundle" => gem_file,
      "lib/ruby/gems/4.1.0/gems/xml-1.0/lib/xml.rb" => "require 'xml.bundle'\n",
      "app/gems/xml/lib/xml.bundle" => gem_file,
    })

    assert_empty plan.problems
    assert_equal({ "libxml2.2.dylib" => LIBXML2 }, plan.sources)
    assert_equal({
      "lib/ruby/gems/4.1.0/gems/xml-1.0/lib/xml.bundle" => [[LIBXML2, "@loader_path/../../../../../../carried/libxml2.2.dylib"]],
      "app/gems/xml/lib/xml.bundle" => [[LIBXML2, "@loader_path/../../../../lib/carried/libxml2.2.dylib"]],
    }, plan.changes)
  end

  # dylibbundler, delocate, and PyInstaller follow a library's own needs
  # without being asked; the project names each one here, so that the
  # app carries nothing its developer did not choose, and one build names
  # every one left out, with the list to write.
  def test_every_library_a_carried_one_needs_must_be_listed_and_one_build_names_them_all
    place(LIBXML2, Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @loader_path/libraylib.600.dylib]))
    place("/opt/homebrew/opt/libxml2/lib/libraylib.600.dylib", Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib], install_name: "@rpath/libraylib.600.dylib"))
    files = { "lib/xml/xml.bundle" => gem_file }

    assert_equal [
      "libxml2.2.dylib, which the app carries from #{LIBXML2}, needs @loader_path/libraylib.600.dylib, which is " \
        "/opt/homebrew/opt/libxml2/lib/libraylib.600.dylib on this computer and which neither macOS nor Fledge's runtime provides. " \
        "If you may distribute it too, list it in fledge.yml as macos: { carried_libraries: [libxml2.2.dylib, libraylib.600.dylib] }.",
    ], carried(["libxml2.2.dylib"], files).problems

    both = carried(["libxml2.2.dylib", "libraylib.600.dylib"], files)
    assert_empty both.problems
    assert_equal ["libraylib.600.dylib", "libxml2.2.dylib"], both.sources.keys.sort
    assert_equal({ "lib/xml/xml.bundle" => [[LIBXML2, "@loader_path/../carried/libxml2.2.dylib"]] }, both.changes,
      "the copy of libxml2 already names libraylib beside itself, so it is left as it is")
  end

  def test_a_listed_library_this_computer_lacks_where_dyld_would_look_is_refused
    assert_equal [
      "lib/xml/xml.bundle needs #{LIBXML2}, which fledge.yml's macos: carried_libraries has the app carry, but this computer has no " \
        "file there, so there is nothing to copy. Install it, or build the gem so that it names the library where it is.",
    ], carried(["libxml2.2.dylib"], { "lib/xml/xml.bundle" => gem_file }).problems

    rpath = carried(["libffi.dylib"], { "lib/ffi/ffi_c.bundle" => Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib @rpath/libffi.dylib]) })
    assert_equal [
      "lib/ffi/ffi_c.bundle needs @rpath/libffi.dylib, which fledge.yml's macos: carried_libraries has the app carry, but none of " \
        "the run paths dyld would search for it on this computer (it has none) leads to a file, so there is nothing to copy. Install " \
        "it, or build the gem so that it names the library where it is.",
    ], rpath.problems
  end

  def test_a_library_for_another_processor_or_a_newer_macos_than_the_apps_is_refused
    place(LIBXML2, Binaries.macho(needed: [], minos: "15.0", cpu: "x86_64"))
    assert_equal [
      "libxml2.2.dylib, which the app is to carry from #{LIBXML2}, has no code for arm64, the processor of the app's Ruby, so the " \
        "app could not load it. Carry a build of it for arm64.",
    ], carried(["libxml2.2.dylib"], { "lib/xml/xml.bundle" => gem_file }).problems

    place(LIBXML2, Binaries.macho(needed: [], minos: "27.0"))
    assert_equal [
      "libxml2.2.dylib, which the app is to carry from #{LIBXML2}, needs macOS 27.0, and apps for arm64-darwin run on macOS 15.0 " \
        "and later. Carry a build of it made for macOS 15.0, such as one compiled with MACOSX_DEPLOYMENT_TARGET=15.0.",
    ], carried(["libxml2.2.dylib"], { "lib/xml/xml.bundle" => gem_file }).problems
  end

  def test_a_listed_library_nothing_needs_is_refused
    place(LIBXML2, Binaries.macho(needed: %w[/usr/lib/libSystem.B.dylib]))
    assert_equal [
      "fledge.yml's macos: carried_libraries lists libextra.dylib, which none of the gems' compiled files, nor the libraries the " \
        "app carries, needs. Remove it.",
    ], carried(["libxml2.2.dylib", "libextra.dylib"], { "lib/xml/xml.bundle" => gem_file }).problems
  end

  def test_nothing_listed_carries_nothing
    plan = carried([], { "lib/xml/xml.bundle" => gem_file })
    assert_equal [[], {}, {}], [plan.problems, plan.sources, plan.changes]
  end
end
