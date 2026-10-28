# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

class DesktopEntryTest < Minitest::Test
  def identity(name: "Hello Window", icon: nil)
    Fledge::Identity.new(name:, kind: "windowed", identifier: "com.example.HelloWindow", version: "1.2.3", publisher: nil,
      copyright: nil, icon:)
  end

  def test_writes_a_desktop_entry_named_for_the_identifier
    entries = Fledge::DesktopEntry.new(identity).entries
    assert_equal ["com.example.HelloWindow.desktop"], entries.map(&:path)
    assert_equal <<~DESKTOP, entries.first.content
      [Desktop Entry]
      Type=Application
      Version=1.5
      Name=Hello Window
      Exec="Hello Window"
      Terminal=false
    DESKTOP
  end

  def test_writes_icons_in_the_hicolor_theme
    icon = Fledge::Icon.new(Fledge::Png.new(width: 1024, height: 1024, pixels: ([1, 2, 3, 255] * (1024 * 1024)).pack("C*")))
    entries = Fledge::DesktopEntry.new(identity(icon:)).entries
    assert_includes entries.first.content, "\nIcon=com.example.HelloWindow\n"
    sizes = entries.drop(1).map { |entry| [entry.path, Fledge::Png.read(entry.content).width] }
    assert_equal Fledge::Icon::LINUX.map { |size| ["share/icons/hicolor/#{size}x#{size}/apps/com.example.HelloWindow.png", size] }, sizes
  end

  def test_escapes_values_and_quotes_the_program
    assert_equal "HelloWindow", Fledge::DesktopEntry.exec("HelloWindow")
    assert_equal '"Hello Window"', Fledge::DesktopEntry.exec("Hello Window")
    assert_equal '"Say \\"Hi\\" \\$5"', Fledge::DesktopEntry.exec('Say "Hi" $5')
    assert_equal "100%%", Fledge::DesktopEntry.exec("100%")
    assert_equal "a\\\\b\\nc\\td", Fledge::DesktopEntry.string("a\\b\nc\td")
    assert_equal "\\sspace", Fledge::DesktopEntry.string(" space")
    assert_includes Fledge::DesktopEntry.new(identity(name: 'Say "Hi"')).text, "Exec=\"Say \\\\\"Hi\\\\\"\"\n"
  end

  # freedesktop.org's own validator accepts it, where it is installed (CI's
  # Delivery on Linux installs it).
  def test_desktop_file_validate_accepts_it
    skip "desktop-file-validate is not installed" unless system("command -v desktop-file-validate > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      entry = Fledge::DesktopEntry.new(identity(name: 'Hello "Window" 100%')).entries.first
      path = File.join(dir, entry.path)
      File.write(path, entry.content)
      out, status = Open3.capture2e("desktop-file-validate", path)
      assert_predicate status, :success?, out
    end
  end
end
