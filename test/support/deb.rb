# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"

# What the tests of Fledge::Deb share (test/deb_test.rb and
# test/integration/deb_dependencies_test.rb): the folder fledge build
# leaves for a windowed app on Linux, the .deb dpkg-deb builds of it, and
# dpkg-deb's reading of it back. Without dpkg-deb the tests that need it
# skip, unless FLEDGE_REQUIRE_DPKG_DEB is set, as CI sets it on Linux.
module DebHelpers
  X86 = Fledge::Platform.find("x86_64-linux")
  ARM = Fledge::Platform.find("aarch64-linux")

  def need_dpkg_deb
    return if system("dpkg-deb", "--version", out: File::NULL, err: File::NULL)

    message = "a .deb is built with dpkg-deb, from Debian's dpkg"
    ENV["FLEDGE_REQUIRE_DPKG_DEB"] ? flunk(message) : skip(message)
  end

  def identity(icon: nil, version: "1.2.3", publisher: "Example, Inc.", identifier: "com.example.MyApp", **about)
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier:, version:, publisher:, copyright: nil, icon:,
      description: nil, long_description: nil, homepage: nil, file_associations: [], **about)
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

  def build(dir, identity: self.identity, platform: X86, system_libraries: [], extension: nil)
    folder = folder(dir, identity)
    if extension
      path = File.join(folder, "lib/ruby/gems/4.0.0/gems/wrapper-1.0.0/lib/wrapper.so")
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(extension, path)
    end
    Fledge::Deb.write(identity:, folder:, platform:, to: File.join(dir, "My App-#{platform.name}.deb"), system_libraries:)
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
end
