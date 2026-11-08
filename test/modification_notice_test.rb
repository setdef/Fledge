# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Fledge::ModificationNotice, the notice a Windows app carries of the
# programs fledge build changed (AGPL-3.0, section 5(a); ADR 004,
# section 10). It is written only on Windows, where assembly_test.rb and
# Delivery read it back from a built app; its text is the same on every
# system, so it is checked here on each.
class ModificationNoticeTest < Minitest::Test
  def identity(**about)
    Fledge::Identity.new(name: "My App", kind: "windowed", identifier: "com.example.MyApp", version: "1.2.3", publisher: "Me",
      copyright: "2026 Me", icon: nil, description: nil, long_description: nil, homepage: nil, file_associations: [], **about)
  end

  # Each program is named with the date of the build, every string and
  # version rcedit wrote into it, and its icon, which this app holds; and
  # the notice says where the launcher's source and the steps are.
  def test_names_each_program_what_was_written_into_it_and_when
    Dir.mktmpdir do |dir|
      app = File.join(dir, "app")
      FileUtils.mkdir_p(File.join(app, "icons"))
      File.write(File.join(app, "icons", "app.ico"), "ico")
      icon = Fledge::Icon.new(base: File.join(dir, "project", "icons", "app"), name: "icons/app")
      programs = { "My App.exe" => identity(icon:), "my-app.exe" => identity(name: "my-app", kind: "console", publisher: nil, copyright: nil) }

      text = Fledge::ModificationNotice.new(programs:, date: Time.utc(2026, 11, 6, 23, 59)).text(app)

      assert_equal <<~TEXT, text
        Programs fledge build changed

        Each program below is a copy of Fledge's launcher, which is under the
        GNU Affero General Public License, version 3 or later (its text is in
        NOTICES.txt, beside this file), that Fledge #{Fledge::VERSION}'s fledge build
        changed on 2026-11-06: it renamed the copy for this app, and had rcedit
        write this version information and icon into the copy's resources,
        from the app's fledge.yml. Nothing else in them was changed.

          My App.exe
            FileVersion and ProductVersion: 1.2.3
            CompanyName: Me
            FileDescription: My App
            InternalName: My App
            LegalCopyright: 2026 Me
            OriginalFilename: My App.exe
            ProductName: My App
            Icon: icons/app.ico, which this app holds as app/icons/app.ico

          my-app.exe
            FileVersion and ProductVersion: 1.2.3
            FileDescription: my-app
            InternalName: my-app
            OriginalFilename: my-app.exe
            ProductName: my-app
            Icon: none

        Their source is Fledge's, at the tag of the version that built this app,
        where runtime/launcher/ holds the launcher's C, and
        lib/fledge/windows_resources.rb the steps that wrote these resources,
        with rcedit, from what is listed above:

          https://github.com/setdef/Fledge/tree/v#{Fledge::VERSION}
      TEXT
    end
  end

  # An icon the project keeps outside the app's folder, or leaves out of
  # it, is named as fledge.yml names it, and the notice says the app does
  # not hold it.
  def test_an_icon_the_app_does_not_hold_is_named_as_fledge_yml_names_it
    Dir.mktmpdir do |dir|
      app = File.join(dir, "app")
      FileUtils.mkdir_p(app)
      File.write(File.join(dir, "art.ico"), "ico")
      icon = Fledge::Icon.new(base: File.join(dir, "art"), name: "../art")

      text = Fledge::ModificationNotice.new(programs: { "My App.exe" => identity(icon:) }, date: Time.utc(2026, 11, 6)).text(app)

      assert_includes text, "    Icon: ../art.ico, from the project that built this app, which this app does not hold\n"
    end
  end

  # The date honors SOURCE_DATE_EPOCH, as the runtime's SBOM does, so a
  # build that sets it writes the same notice, and is the day in UTC; a
  # malformed one fails the build, as reproducible-builds.org's
  # specification asks.
  def test_the_date_is_source_date_epoch_when_it_is_set
    assert_equal Time.at(1_793_923_200).utc, Fledge::ModificationNotice.date({ "SOURCE_DATE_EPOCH" => "1793923200" })
    assert_in_delta Time.now.to_f, Fledge::ModificationNotice.date({}).to_f, 60
    error = assert_raises(Fledge::Error) { Fledge::ModificationNotice.date({ "SOURCE_DATE_EPOCH" => "yesterday" }) }
    assert_equal "SOURCE_DATE_EPOCH is \"yesterday\", which is not a count of seconds since 1970", error.message
  end
end
