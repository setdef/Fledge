# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

# Fledge::Deb, which has dpkg-deb build a .deb of the built app's folder
# (ADR 021), read back with dpkg-deb itself. CI's Delivery installs one
# with apt in Debian and Ubuntu containers, runs the app, and removes it
# (.github/scripts/deliver-deb.sh). Without dpkg-deb the tests that need
# it skip, unless FLEDGE_REQUIRE_DPKG_DEB is set, as CI sets it on Linux.
class DebTest < Minitest::Test
  X86 = Fledge::Platform.find("x86_64-linux")
  ARM = Fledge::Platform.find("aarch64-linux")

  def need_dpkg_deb
    return if system("dpkg-deb", "--version", out: File::NULL, err: File::NULL)

    message = "a .deb is built with dpkg-deb, from Debian's dpkg"
    ENV["FLEDGE_REQUIRE_DPKG_DEB"] ? flunk(message) : skip(message)
  end

  def identity(icon: nil, version: "1.2.3", publisher: "Example, Inc.", identifier: "com.example.MyApp")
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier:, version:, publisher:, copyright: nil, icon:)
  end

  # Writes the folder fledge build leaves for a windowed app on Linux:
  # the program, a runtime file, a link, the notices, and, with an icon,
  # the desktop entry and the hicolor icons, as Fledge::DesktopEntry
  # writes them.
  def folder(dir, identity)
    folder = File.join(dir, "My App-x86_64-linux")
    Fledge::Entry.file("My App", "#!/bin/sh\n", mode: 0o755).write_into(folder)
    Fledge::Entry.file("ruby/bin/ruby", "ruby", mode: 0o755).write_into(folder)
    Fledge::Entry.file("notices/NOTICES.txt", "notices\n").write_into(folder)
    File.symlink("bin/ruby", File.join(folder, "ruby/ruby"))
    Fledge::DesktopEntry.new(identity).entries.each { |entry| entry.write_into(folder) }
    folder
  end

  def build(dir, identity: self.identity, platform: X86)
    Fledge::Deb.write(identity:, folder: folder(dir, identity), platform:, to: File.join(dir, "My App-#{platform.name}.deb"))
  end

  def field(deb, name)
    out, status = Open3.capture2e("dpkg-deb", "--field", deb, name)
    assert_predicate status, :success?, out
    out.strip
  end

  def contents(deb)
    out, status = Open3.capture2e("dpkg-deb", "--contents", deb)
    assert_predicate status, :success?, out
    out
  end

  # Policy 5.6: a package name is lower case letters, digits, plus, minus,
  # and full stops; the identifier's letters are lower-cased.
  def test_the_control_file_comes_from_what_fledge_yml_says
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      deb = build(dir)

      assert_equal "com.example.myapp", field(deb, "Package")
      assert_equal "1.2.3", field(deb, "Version")
      assert_equal "amd64", field(deb, "Architecture")
      assert_equal "Example, Inc.", field(deb, "Maintainer")
      assert_equal "My App", field(deb, "Description")
      assert_equal "libc6 (>= 2.39)", field(deb, "Depends")
      assert_equal "optional", field(deb, "Priority")
      assert_operator field(deb, "Installed-Size").to_i, :>, 0
    end
  end

  def test_an_arm_platform_is_arm64_and_a_pre_release_sorts_before_its_release
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      deb = build(dir, identity: identity(version: "1.2.3.pre.4"), platform: ARM)

      assert_equal "arm64", field(deb, "Architecture")
      assert_equal "1.2.3~pre.4", field(deb, "Version")
    end
  end

  def test_with_no_publisher_the_maintainer_is_the_apps_name
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      assert_equal "My App", field(build(dir, identity: identity(publisher: nil)), "Maintainer")
    end
  end

  # The app goes under /usr/lib/PACKAGE (policy 9.1.1 allows a mixture of
  # files there); its desktop entry and icons go where desktops look.
  def test_the_app_the_desktop_entry_and_the_icons_are_installed_where_a_desktop_finds_them
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(dir)
      listed = contents(build(dir, identity: identity(icon: Fledge::Icon.new(base: File.join(dir, "icon"), name: "icon"))))

      assert_match %r{^-rwxr-xr-x root/root .* \./usr/lib/com\.example\.myapp/My App$}, listed
      assert_match %r{ \./usr/lib/com\.example\.myapp/ruby/ruby -> bin/ruby$}, listed
      assert_match %r{ \./usr/lib/com\.example\.myapp/notices/NOTICES\.txt$}, listed
      assert_match %r{ \./usr/share/applications/com\.example\.MyApp\.desktop$}, listed
      assert_match %r{ \./usr/share/icons/hicolor/256x256/apps/com\.example\.MyApp\.png$}, listed
      refute_match %r{ \./usr/lib/com\.example\.myapp/(com\.example\.MyApp\.desktop|share)}, listed
      assert_empty listed.lines.grep_v(%r{ root/root }), "every entry belongs to root"
    end
  end

  def test_the_desktop_entry_runs_the_program_by_its_installed_path
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      FakeRuntime.icons(dir)
      deb = build(dir, identity: identity(icon: Fledge::Icon.new(base: File.join(dir, "icon"), name: "icon")))
      out, status = Open3.capture2e("dpkg-deb", "--fsys-tarfile", deb)
      assert_predicate status, :success?, out
      entry, = Open3.capture2("tar", "-xO", "./usr/share/applications/com.example.MyApp.desktop", stdin_data: out)

      assert_includes entry, "Exec=\"/usr/lib/com.example.myapp/My App\"\n"
      assert_includes entry, "Icon=com.example.MyApp\n"
    end
  end

  def test_a_computer_without_dpkg_deb_is_told_what_to_install
    Dir.mktmpdir do |dir|
      path = ENV.fetch("PATH")
      ENV["PATH"] = dir
      error = assert_raises(Fledge::Error) { build(dir) }

      assert_includes error.message, "fledge build needs dpkg-deb"
      assert_includes error.message, "sudo apt install dpkg"
    ensure
      ENV["PATH"] = path
    end
  end
end
