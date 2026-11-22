# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/deb"
require_relative "support/binaries"

# Fledge::Deb, which has dpkg-deb build a .deb of the built app's folder,
# read back with dpkg-deb itself (test/support/deb.rb).
# test/integration/deb_dependencies_test.rb covers what a gem's compiled
# extension makes it depend on. CI's Delivery installs one with apt in
# Debian and Ubuntu containers, runs the app, and removes it
# (.github/scripts/deliver-deb.sh).
class DebTest < Minitest::Test
  include DebHelpers

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
      assert_equal "libc6 (>= 2.28)", field(deb, "Depends")
      assert_equal "optional", field(deb, "Priority")
      assert_operator field(deb, "Installed-Size").to_i, :>, 0
    end
  end

  # A gem's compiled file needs the glibc it was compiled with, which may
  # be newer than the runtime's floor: the package depends on the glibc
  # the build read from the app's files and recorded
  # (NativeBuild::Floors.glibc), so apt refuses an older system, saying
  # why, rather than the app failing to load the file there. The package
  # reads no file for it, so a .deb made with no objdump at hand says
  # the same.
  def test_glibc_is_the_one_the_build_read_from_the_apps_files
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      deb = build(dir, glibc: "2.41", files: { "plain.so" => Binaries.elf(needed: %w[libc.so.6]) })

      assert_equal "libc6 (>= 2.41)", field(deb, "Depends")
    end
  end

  # A typelib fledge.yml lists is a dependency on the package named for
  # it as Debian's GObject introspection packages are, gir1.2- and the
  # namespace and version in lower case, which the package that holds
  # it is or provides: Gdk-4.0's is gir1.2-gtk-4.0, which provides
  # gir1.2-gdk-4.0.
  def test_a_typelib_listed_as_the_distributions_is_a_dependency_on_its_package
    need_dpkg_deb
    Dir.mktmpdir do |dir|
      deb = build(dir, system_typelibs: %w[Gtk-4.0 Gdk-4.0 GdkPixbuf-2.0])

      assert_equal "libc6 (>= 2.28), gir1.2-gtk-4.0, gir1.2-gdk-4.0, gir1.2-gdkpixbuf-2.0", field(deb, "Depends")
    end
  end

  # Debian's GObject introspection mini-policy, section 2: an underscore
  # in the namespace becomes a hyphen, as a package name has none, and a
  # typelib listed twice is one dependency.
  def test_a_typelib_package_name_replaces_underscores_and_is_named_once
    assert_equal %w[gir1.2-gtk-4.0 gir1.2-foo-bar-1.0], Fledge::Deb.typelib_packages(%w[Gtk-4.0 Foo_Bar-1.0 Gtk-4.0])
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
      deb = Fledge::Deb.write(identity:, folder: folder(dir, identity), platform: X86, to: File.join(dir, "My App.deb"), glibc: "2.28",
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

  # A file type the app defines goes where shared-mime-info's trigger
  # finds it, so that dpkg compiles it into the database at install.
  def test_a_file_type_the_app_defines_is_installed_where_shared_mime_info_finds_it
    need_dpkg_deb
    game = Fledge::Config::FileAssociation.new(name: "Game", role: "viewer", extensions: ["game"], mime_types: ["application/x-game"],
      content_types: [], folders: false, defines_type: true)
    Dir.mktmpdir do |dir|
      listed = contents(build(dir, identity: identity(file_associations: [game])))

      assert_match %r{^-rw-r--r-- root/root .* \./usr/share/mime/packages/com\.example\.MyApp\.xml$}, listed
      refute_match %r{ \./usr/lib/com\.example\.myapp/share}, listed
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
