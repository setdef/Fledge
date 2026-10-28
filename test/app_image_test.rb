# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

# Fledge::AppImage on Linux, where AppImages are built (ADR 010): the
# runtime, then the SquashFS that mksquashfs wrote of the app's folder
# laid out as an AppDir, read back with unsquashfs. CI's Delivery runs a
# real one, with FUSE and without (.github/scripts/deliver-appimage.sh).
# Without mksquashfs the tests skip, unless FLEDGE_REQUIRE_MKSQUASHFS is
# set, as CI sets it on Linux.
class AppImageTest < Minitest::Test
  RUNTIME = Fledge::Entry.file("appimage-runtime", "\x7FELF#{'runtime' * 100}".b, mode: 0o755)

  def setup
    return if RUBY_PLATFORM.include?("linux") && system("mksquashfs", "-version", out: File::NULL, err: File::NULL)

    message = "an AppImage is built on Linux, with squashfs-tools' mksquashfs"
    ENV["FLEDGE_REQUIRE_MKSQUASHFS"] ? flunk(message) : skip(message)
  end

  def identity(icon: nil)
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier: "com.example.MyApp", version: "1.0", publisher: nil,
      copyright: nil, icon:)
  end

  # Writes the AppImage of a folder with the app's program and desktop
  # entry, with RUNTIME in its runtime's tools folder unless +tools+ says
  # otherwise, and returns its path.
  def build(dir, identity: self.identity, tools: :runtime)
    folder = File.join(dir, "My App-x86_64-linux")
    Fledge::Entry.file("My App", "#!/bin/sh\n", mode: 0o755).write_into(folder)
    Fledge::Entry.file("com.example.MyApp.desktop", "[Desktop Entry]\n").write_into(folder)
    installer = File.join(dir, "tools")
    RUNTIME.write_into(installer)
    Fledge::AppImage.write(identity:, folder:, tools: (tools == :runtime) ? installer : tools, to: "#{folder}.AppImage")
  end

  # What unsquashfs lists in the AppImage's file system, after the
  # runtime: each path, with its mode and its link's target.
  def listing(path)
    out, status = Open3.capture2e("unsquashfs", "-o", RUNTIME.content.bytesize.to_s, "-lls", "-d", "", path)
    assert_predicate status, :success?, out
    out
  end

  def test_the_runtime_comes_first_and_the_file_system_after_it
    Dir.mktmpdir do |dir|
      path = build(dir)
      assert_equal File.join(dir, "My App-x86_64-linux.AppImage"), path

      bytes = File.binread(path)
      assert_equal RUNTIME.content, bytes.byteslice(0, RUNTIME.content.bytesize)
      assert_equal "hsqs", bytes.byteslice(RUNTIME.content.bytesize, 4)
      assert_equal 0o755, File.stat(path).mode & 0o777
      assert_match %r{^-rwxr-xr-x root/root .* /My App$}, listing(path)
    end
  end

  # AppImage's AppDir: AppRun runs the app's program, and with an icon,
  # the icon at the top under the desktop entry's Icon name, and
  # .DirIcon linked to it.
  def test_the_file_system_is_an_appdir_with_apprun_and_the_icon
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(dir)
      listed = listing(build(dir, identity: identity(icon: Fledge::Icon.new(base: File.join(dir, "icon"), name: "icon"))))

      assert_match %r{ /AppRun -> My App$}, listed
      assert_match %r{ /\.DirIcon -> com\.example\.MyApp\.png$}, listed
      assert_match %r{ /com\.example\.MyApp\.png$}, listed
      assert_match %r{ /com\.example\.MyApp\.desktop$}, listed
    end
  end

  def test_a_runtime_without_an_appimage_runtime_is_refused
    Dir.mktmpdir do |dir|
      [nil, dir].each do |tools|
        error = assert_raises(Fledge::Error) { build(dir, tools:) }
        assert_includes error.message, "the runtime has no tools/appimage-runtime"
      end
    end
  end
end
