# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"

class DesktopEntryTest < Minitest::Test
  def identity(name: "Hello Window", icon: nil, description: nil, file_associations: [])
    Fledge::Identity.new(name:, kind: "windowed", identifier: "com.example.HelloWindow", version: "1.2.3", publisher: nil,
      copyright: nil, icon:, description:, long_description: nil, homepage: nil, file_associations:)
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

  # Each of the developer's PNGs goes, as it is, into the hicolor
  # theme's folder of its size.
  def test_writes_icons_in_the_hicolor_theme
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(dir)
      entries = Fledge::DesktopEntry.new(identity(icon: Fledge::Icon.new(base: File.join(dir, "icon"), name: "icon"))).entries
      assert_includes entries.first.content, "\nIcon=com.example.HelloWindow\n"
      expected = Fledge::Icon::LINUX.map do |size|
        ["share/icons/hicolor/#{size}x#{size}/apps/com.example.HelloWindow.png", File.binread(File.join(dir, "icon-#{size}.png"))]
      end
      assert_equal expected, entries.drop(1).map { |entry| [entry.path, entry.content] }
    end
  end

  # A project with some of the six sizes, as icon tools make them (32,
  # 128, and 256), ships those, each in its own size's folder.
  def test_writes_only_the_icon_sizes_there_are
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(dir)
      [16, 64, 512].each { |size| File.delete(File.join(dir, "icon-#{size}.png")) }
      entries = Fledge::DesktopEntry.new(identity(icon: Fledge::Icon.new(base: File.join(dir, "icon"), name: "icon"))).entries
      assert_equal %w[32x32 128x128 256x256].map { |size| "share/icons/hicolor/#{size}/apps/com.example.HelloWindow.png" }, entries.drop(1).map(&:path)
      assert_equal File.binread(File.join(dir, "icon-128.png")), entries[2].content
    end
  end

  # The description is the entry's Comment, a menu's tooltip, escaped as
  # a string.
  def test_the_description_is_the_comment
    text = Fledge::DesktopEntry.new(identity(description: " Says\thello")).text
    assert_equal "Name=Hello Window\nComment=\\sSays\\thello\nExec=\"Hello Window\"\n", text.lines[3, 3].join
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

  # The files and folders the app opens (ADR 052), as a desktop knows
  # them: by MIME type, inode/directory for folders, once each; and %F,
  # so a file manager passes their paths as arguments. An entry with
  # only extensions names no MIME type, and adds nothing.
  def test_lists_the_mime_types_the_app_opens_and_takes_their_paths
    association = Fledge::Config::FileAssociation
    file_associations = [
      association.new(name: "Folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true),
      association.new(name: "Zip", role: "editor", extensions: ["zip"], mime_types: ["application/zip", "application/x-zip"],
        content_types: [], folders: false),
      association.new(name: "Also zip", role: "viewer", extensions: [], mime_types: ["application/zip"], content_types: [], folders: false),
    ]
    text = Fledge::DesktopEntry.new(identity(file_associations:)).text

    assert_includes text, "\nExec=\"Hello Window\" %F\n"
    assert_includes text, "\nMimeType=inode/directory;application/zip;application/x-zip;\n"
    only_extensions = [association.new(name: "Text", role: "viewer", extensions: ["txt"], mime_types: [], content_types: [], folders: false)]
    assert_equal Fledge::DesktopEntry.new(identity).text, Fledge::DesktopEntry.new(identity(file_associations: only_extensions)).text
    skip "desktop-file-validate is not installed" unless system("command -v desktop-file-validate > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "com.example.HelloWindow.desktop")
      File.write(path, text)
      out, status = Open3.capture2e("desktop-file-validate", path)
      assert_predicate status, :success?, out
    end
  end
end
