# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "zlib"

# Fledge::AppImage: the runtime, then a SquashFS of the app's folder laid
# out as an AppDir. CI's Delivery runs a real one on Linux, with FUSE and
# without (.github/scripts/deliver-appimage.sh).
class AppImageTest < Minitest::Test
  RUNTIME = Fledge::Entry.file("appimage-runtime", "\x7FELF#{'runtime' * 100}".b, mode: 0o755)
  ICON = Fledge::Png.new(width: 1024, height: 1024, pixels: ([40, 80, 160, 255] * (1024 * 1024)).pack("C*"))

  def identity(icon: nil)
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier: "com.example.MyApp", version: "1.0", publisher: nil,
      copyright: nil, icon: icon && Fledge::Icon.new(icon))
  end

  # Writes the AppImage of a folder with the app's program and desktop
  # entry, with RUNTIME in its runtime's installer folder unless +kit+
  # says otherwise, and returns its path.
  def build(dir, identity: self.identity, kit: :runtime)
    folder = File.join(dir, "My App-x86_64-linux")
    Fledge::Entry.file("My App", "#!/bin/sh\n", mode: 0o755).write_into(folder)
    Fledge::Entry.file("com.example.MyApp.desktop", "[Desktop Entry]\n").write_into(folder)
    installer = File.join(dir, "installer")
    RUNTIME.write_into(installer)
    Fledge::AppImage.write(identity:, folder:, kit: (kit == :runtime) ? installer : kit, to: "#{folder}.AppImage")
  end

  # The first metadata block of the directory table (squashfs-tools-ng's
  # format.adoc): where the superblock says it is, a 16-bit size, then
  # zlib, or the block as it is when its top bit says so.
  def directory_table(squashfs)
    start = squashfs.byteslice(72, 8).to_s.unpack1("Q<")
    header = squashfs.byteslice(start, 2).to_s.unpack1("v")
    block = squashfs.byteslice(start + 2, header & 0x7FFF).to_s
    header.anybits?(0x8000) ? block : Zlib::Inflate.inflate(block)
  end

  def test_the_runtime_comes_first_and_the_file_system_after_it_and_it_runs
    Dir.mktmpdir do |dir|
      path = build(dir)
      assert_equal File.join(dir, "My App-x86_64-linux.AppImage"), path

      bytes = File.binread(path)
      assert_equal RUNTIME.content, bytes.byteslice(0, RUNTIME.content.bytesize)
      assert_equal 0x73717368, bytes.byteslice(RUNTIME.content.bytesize, 4).to_s.unpack1("V")
      assert_equal 0o755, File.stat(path).mode & 0o777 unless Gem.win_platform?
    end
  end

  # AppImage's AppDir: AppRun runs the app's program, and with an icon,
  # the icon at the top under the desktop entry's Icon name, and
  # .DirIcon linked to it.
  def test_the_file_system_is_an_appdir_with_apprun_and_the_icon
    Dir.mktmpdir do |dir|
      path = build(dir, identity: identity(icon: ICON))

      squashfs = File.binread(path).byteslice((RUNTIME.content.bytesize)..).to_s
      assert_equal 6, squashfs.unpack1("x4V"), "the root, My App, its desktop entry, AppRun, the icon, and .DirIcon"
      listing = directory_table(squashfs)
      [".DirIcon", "AppRun", "My App", "com.example.MyApp.desktop", "com.example.MyApp.png"].each { |name| assert_includes listing, name }
    end
  end

  def test_a_runtime_without_an_appimage_runtime_is_refused
    Dir.mktmpdir do |dir|
      [nil, dir].each do |kit|
        error = assert_raises(Fledge::Error) { build(dir, kit:) }
        assert_includes error.message, "the runtime has no installer/appimage-runtime"
      end
    end
  end
end
