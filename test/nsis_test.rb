# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "open3"

# Fledge::Nsis: the script it writes, and, where FLEDGE_RUNTIME_DIR holds
# the Windows runtime and this computer's makensis (as CI's test jobs
# do), the installer that makensis compiles from it. Delivery installs a
# real one on Windows (.github/scripts/deliver-installer.ps1).
class NsisTest < Minitest::Test
  def identity(name: "My App", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", version: "1.2.3.pre.4")
    Fledge::Identity.new(name:, kind: "windowed", identifier: "com.example.MyApp", version:, publisher:, copyright:, icon: nil)
  end

  def setup_program(identity: self.identity, folder: "/dist/My App-x64-mingw-ucrt")
    nsis = Fledge::Nsis.new(identity:, folder:, to: "/dist/My App-x64-mingw-ucrt-setup.exe", makensis: "makensis")
    [
      Fledge::Entry.directory("ruby"),
      Fledge::Entry.directory("ruby/bin"),
      Fledge::Entry.file("ruby/bin/ruby.dll", "x" * 3000),
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755),
      Fledge::Entry.directory("app"),
      Fledge::Entry.file("app/$main.rb", "puts 1\n"),
    ].each { |entry| nsis.add(entry) }
    nsis
  end

  def script(**) = setup_program(**).script(icon: nil)

  # makensis reads paths of the computer it runs on; on Windows, with
  # backslashes.
  def test_paths_are_this_computers
    assert_equal File.expand_path("a/b"), Fledge::Nsis.host_path("a/b").tr("\\", "/")
    assert_equal Gem.win_platform?, Fledge::Nsis.host_path("a/b").include?("\\")
  end

  # Tauri's currentUser mode: no administrator, and a folder of the
  # person's own, here FOLDERID_UserProgramFiles.
  def test_it_installs_for_the_person_with_no_administrator
    lines = script.lines.map(&:chomp)

    assert_equal "Unicode true", lines.first
    assert_includes lines, "RequestExecutionLevel user"
    assert_includes lines, "InstallDir \"$LOCALAPPDATA\\Programs\\My App\""
    assert_includes lines, "SetCompressor /SOLID zlib"
    assert_includes lines, "  File /r \"#{Fledge::Nsis.host_path('/dist/My App-x64-mingw-ucrt/*')}\""
    assert_includes lines, "OutFile \"#{Fledge::Nsis.host_path('/dist/My App-x64-mingw-ucrt-setup.exe')}\""
  end

  # The Start menu shortcut, with its System.AppUserModel.ID set to the
  # identifier the launcher gives the process (ADR 008, section 3).
  def test_the_start_menu_shortcut_carries_the_app_user_model_id
    text = script

    assert_includes text, "  CreateShortcut \"$SMPROGRAMS\\My App.lnk\" \"$INSTDIR\\My App.exe\"\n  !insertmacro FledgeSetAppUserModelId \"$SMPROGRAMS\\My App.lnk\"\n"
    assert_includes text, "System::Call '*(&w18 \"com.example.MyApp\")p.r4'"
    assert_includes text, "${PKEY_AppUserModel_ID}"
    assert_includes text, "${VT_LPWSTR}"
    assert_includes text, "!include Win\\Propkey.nsh"
  end

  # A desktop shortcut only when the person checks the box, which starts
  # unchecked, and never in a silent install, which shows no pages.
  def test_a_desktop_shortcut_is_offered_unchecked
    lines = script.lines.map(&:chomp)

    assert_includes lines, "!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED"
    assert_includes lines, "!define MUI_FINISHPAGE_SHOWREADME_FUNCTION CreateDesktopShortcut"
    assert_equal 1, lines.count { |line| line.include?("CreateShortcut \"$DESKTOP") }
  end

  def test_the_uninstaller_is_registered_for_the_person_and_removes_what_it_installed
    lines = script.lines.map(&:chomp)
    key = "\"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\com.example.MyApp\""

    assert_includes lines, "  WriteUninstaller \"$INSTDIR\\uninstall.exe\""
    assert_includes lines, "  WriteRegStr HKCU #{key} \"DisplayName\" \"My App\""
    assert_includes lines, "  WriteRegStr HKCU #{key} \"DisplayVersion\" \"1.2.3.pre.4\""
    assert_includes lines, "  WriteRegStr HKCU #{key} \"Publisher\" \"Example, Inc.\""
    assert_includes lines, "  WriteRegStr HKCU #{key} \"QuietUninstallString\" '\"$INSTDIR\\uninstall.exe\" /S'"
    assert_includes lines, "  WriteRegDWORD HKCU #{key} \"EstimatedSize\" 3"
    assert_includes lines, "  DeleteRegKey HKCU #{key}"
    uninstall = lines.drop_while { |line| line != "Section Uninstall" }
    assert_equal ["  Delete \"$INSTDIR\\ruby\\bin\\ruby.dll\"", "  Delete \"$INSTDIR\\My App.exe\"", "  Delete \"$INSTDIR\\app\\$$main.rb\""],
      uninstall.grep(/Delete "\$INSTDIR\\(?!uninstall)/)
    assert_equal ["  RMDir \"$INSTDIR\\ruby\\bin\"", "  RMDir \"$INSTDIR\\app\"", "  RMDir \"$INSTDIR\\ruby\"", "  RMDir $INSTDIR"], uninstall.grep(/RMDir/)
  end

  def test_a_new_version_runs_the_old_uninstaller_first
    assert_includes script, "  ExecWait '\"$INSTDIR\\uninstall.exe\" /S _?=$INSTDIR'\n"
  end

  # The setup program's own version information, which makensis writes:
  # four numbers, and the version as written.
  def test_the_setup_program_carries_the_apps_version_information
    lines = script.lines.map(&:chomp)

    assert_includes lines, "VIProductVersion 1.2.3.0"
    assert_includes lines, "VIAddVersionKey ProductVersion \"1.2.3.pre.4\""
    assert_includes lines, "VIAddVersionKey FileDescription \"My App Setup\""
    assert_includes lines, "VIAddVersionKey LegalCopyright \"© 2026 Example, Inc.\""
    refute_includes script(identity: identity(publisher: nil, copyright: nil)), "CompanyName"
    assert_includes setup_program.script(icon: "/tmp/app.ico"), "!define MUI_ICON \"#{Fledge::Nsis.host_path('/tmp/app.ico')}\""
  end

  # A dollar sign doubled and a double quote as $\", so NSIS reads the
  # name as it is.
  def test_names_are_escaped_as_nsis_strings
    text = script(identity: identity(name: "Say \"$1\""))

    assert_includes text, "Name \"Say $\\\"$$1$\\\"\"\n"
  end

  def test_a_runtime_without_nsis_is_refused
    Dir.mktmpdir do |dir|
      nsis = Fledge::Nsis.new(identity:, folder: dir, to: File.join(dir, "setup.exe"), makensis: "makensis")

      assert_match(%r{the runtime has no installer/nsis}, assert_raises(Fledge::Error) { nsis.finish({}) }.message)
    end
  end

  def test_makensis_compiles_the_installer
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    windows = File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.find("x64-mingw-ucrt")))
    makensis = File.join(runtimes, Fledge::Runtimes.makensis_file_name(Fledge::Platform.local))
    unless File.file?(windows) && File.file?(makensis)
      flunk "no Windows runtime and makensis in #{runtimes}" if ENV["FLEDGE_REQUIRE_MAKENSIS"]
      skip "makensis and the Windows runtime are in CI's FLEDGE_RUNTIME_DIR"
    end

    Dir.mktmpdir do |dir|
      kit = {}
      Fledge::TarGz.each_entry(windows) do |entry|
        rest = entry.path.split("/", 2).last.to_s
        kit[rest.delete_prefix("installer/")] = entry if rest.start_with?("installer/") && entry.type == :file
      end
      folder = File.join(dir, "My App-x64-mingw-ucrt")
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755).write_into(folder)
      program = Fledge::Runtimes.new(env: { "FLEDGE_RUNTIME_DIR" => runtimes, "XDG_CACHE_HOME" => File.join(dir, "cache") })
        .makensis(Fledge::Platform.local)
      nsis = Fledge::Nsis.new(identity:, folder:, to: "#{folder}-setup.exe", makensis: program)
      nsis.add(Fledge::Entry.file("My App.exe", "MZ", mode: 0o755))

      path = nsis.finish(kit)
      assert_equal "MZ", File.binread(path, 2)
      assert_includes File.binread(path), "My App Setup".encode(Encoding::UTF_16LE).b, "its version information names it"
    end
  end
end
