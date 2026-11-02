# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class InstallersTest < Minitest::Test
  MACOS = Fledge::Platform.find("arm64-darwin")
  LINUX = Fledge::Platform.find("aarch64-linux")
  WINDOWS = Fledge::Platform.find("x64-mingw-ucrt")

  def app(dir, yaml)
    root = FakeApp.write(dir)
    File.write(File.join(root, "fledge.yml"), yaml)
    Fledge::App.at(root)
  end

  # Tauri builds every installer a platform has unless told otherwise.
  def test_a_windowed_app_gets_every_installer_its_platform_has
    Dir.mktmpdir do |dir|
      windowed = app(dir, "kind: windowed\nidentifier: com.example.Hello\n")

      assert_equal [["dmg"], ["appimage"], ["nsis"]], [MACOS, LINUX, WINDOWS].map { |platform| Fledge::Installers.formats(windowed, platform) }
    end
  end

  def test_fledge_yml_chooses_the_installers_or_none
    Dir.mktmpdir do |dir|
      chosen = app(dir, "kind: windowed\nidentifier: com.example.Hello\ninstallers: [nsis]\n")

      assert_equal [[], [], ["nsis"]], [MACOS, LINUX, WINDOWS].map { |platform| Fledge::Installers.formats(chosen, platform) }
    end
    Dir.mktmpdir do |dir|
      none = app(dir, "kind: windowed\nidentifier: com.example.Hello\ninstallers: []\n")

      assert_empty Fledge::Installers.formats(none, WINDOWS)
    end
  end

  # A .deb needs dpkg-deb, which not every Linux computer has, so it is
  # asked for; and it is for glibc Linux, so a list that asks for it
  # builds none on musl, as it builds no setup program on a Mac.
  def test_a_deb_is_asked_for_and_is_for_glibc_linux
    Dir.mktmpdir do |dir|
      chosen = app(dir, "kind: windowed\nidentifier: com.example.Hello\ninstallers: [dmg, nsis, appimage, deb]\n")
      musl = Fledge::Platform.find("x86_64-linux-musl")

      assert_equal [["dmg"], ["appimage", "deb"], ["nsis"], ["appimage"]], [MACOS, LINUX, WINDOWS, musl].map { |platform| Fledge::Installers.formats(chosen, platform) }
    end
  end

  def test_a_console_app_gets_none
    Dir.mktmpdir do |dir|
      assert_empty Fledge::Installers.formats(Fledge::App.at(FakeApp.write(dir)), MACOS)
    end
  end

  def test_each_is_named_after_the_archive
    assert_equal ["A-arm64-darwin.dmg", "A-x64-mingw-ucrt-setup.exe", "A-aarch64-linux.AppImage", "A-aarch64-linux.deb"],
      [["dmg", MACOS], ["nsis", WINDOWS], ["appimage", LINUX], ["deb", LINUX]].map { |format, platform| Fledge::Installers.file_name(format, "A-#{platform}") }
  end
end
