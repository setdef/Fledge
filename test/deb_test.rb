# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
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

  # A gem's extension, compiled here, that needs zlib from the
  # distribution, as a wrapper of a desktop library needs that library.
  # Every Debian and Ubuntu has zlib1g; only its library is needed, not
  # its headers.
  def zlib_extension(dir)
    shlibdeps = system("dpkg-shlibdeps", "--version", out: File::NULL, err: File::NULL)
    compiler = system("cc", "--version", out: File::NULL, err: File::NULL)
    unless shlibdeps && compiler
      message = "a .deb depends on what dpkg-shlibdeps, from Debian's dpkg-dev, finds, here for a file cc compiles"
      ENV["FLEDGE_REQUIRE_DPKG_DEB"] ? flunk(message) : skip(message)
    end
    path = File.join(dir, "wrapper.so")
    source = "const char *zlibVersion(void);\nconst char *wrapper_version(void) { return zlibVersion(); }\n"
    out, status = Open3.capture2e("cc", "-shared", "-fPIC", "-x", "c", "-", "-o", path, "-l:libz.so.1", stdin_data: source)
    assert_predicate status, :success?, out
    path
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

  # Policy 5.6.13 and 5.6.23: the description is the synopsis, the long
  # description its extended lines, and the homepage a field of its own.
  def test_the_description_and_homepage_are_the_packages
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      about = { description: "Says hello", long_description: "A window.\n\nIt says\thello.\n", homepage: "https://example.com/my-app" }
      deb = build(dir, identity: identity(**about))
      assert_equal "Says hello\n A window.\n .\n It says hello.", field(deb, "Description")
      assert_equal "https://example.com/my-app", field(deb, "Homepage")
    end
    Dir.mktmpdir { |dir| assert_equal "", field(build(dir), "Homepage") }
  end

  # Policy 12.5 and 12.7: the license text, uncompressed, as the
  # package's copyright file, and the changelog as changelog.gz, by
  # gzip -9 -n, with no name or time in it; neither without the keys.
  def test_the_license_and_changelog_are_the_packages_documents
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      changelog = File.join(dir, "CHANGES.txt")
      File.write(changelog, "My App 1.2.3\n\n  * Says hello.\n")
      deb = Fledge::Deb.write(identity:, folder: folder(dir, identity), platform: X86, to: File.join(dir, "My App.deb"),
        license: "Copyright © 2026 Me\n", changelog:)
      listed = contents(deb)
      assert_match %r{^-rw-r--r-- root/root .* \./usr/share/doc/com\.example\.myapp/copyright$}, listed
      assert_match %r{^-rw-r--r-- root/root .* \./usr/share/doc/com\.example\.myapp/changelog\.gz$}, listed
      refute_match %r{doc/com\.example\.myapp/changelog$}, listed

      out = File.join(dir, "out")
      _, status = Open3.capture2e("dpkg-deb", "-x", deb, out)
      assert_predicate status, :success?
      doc = File.join(out, "usr/share/doc/com.example.myapp")
      assert_equal "Copyright © 2026 Me\n", File.read(File.join(doc, "copyright"))
      gz = File.binread(File.join(doc, "changelog.gz"))
      assert_equal [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 2], gz.bytes.first(9), "gzip -n -9: no name, no time, the best compression"
      assert_equal File.read(changelog), Zlib.gunzip(gz)
    end
    Dir.mktmpdir { |dir| refute_match %r{usr/share/doc}, contents(build(dir)) }
  end

  def test_an_extended_description_is_written_as_policy_asks
    assert_equal " One.\n .\n Two,\n   indented.\n", Fledge::Deb.extended("\nOne.\n\nTwo,\n  indented.  \n")
    assert_equal "", Fledge::Deb.extended(nil)
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

  # ADR 030: a library fledge.yml lists as the distribution's becomes a
  # dependency on the package that provides it, as dpkg-shlibdeps finds
  # it for the files that need it, beside glibc's, which stays the
  # runtime's. With nothing listed, glibc's stays the only one, whatever
  # the gems' files need.
  def test_a_library_listed_as_the_distributions_is_a_dependency_on_its_package
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      extension = zlib_extension(dir)
      depends = field(build(File.join(dir, "listed").tap { |d| FileUtils.mkdir_p(d) }, extension:, system_libraries: ["libz.so.1"]), "Depends")
      plain = field(build(File.join(dir, "plain").tap { |d| FileUtils.mkdir_p(d) }, extension:), "Depends")

      assert_match(/\Alibc6 \(>= 2\.39\), zlib1g \(>= [^)]+\)\z/, depends)
      assert_equal "libc6 (>= 2.39)", plain
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
