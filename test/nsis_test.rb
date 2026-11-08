# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "open3"

# Fledge::Nsis: the script it writes, and, on Windows, where
# FLEDGE_RUNTIME_DIR holds the Windows runtime (as CI's Windows test job
# does), the installer that the runtime's makensis compiles from it.
# Delivery installs a real one on Windows
# (.github/scripts/deliver-installer.ps1).
class NsisTest < Minitest::Test
  def identity(name: "My App", publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", version: "1.2.3.pre.4", homepage: nil, file_associations: [])
    Fledge::Identity.new(name:, kind: "windowed", identifier: "com.example.MyApp", version:, publisher:, copyright:, icon: nil,
      description: nil, long_description: nil, homepage:, file_associations:)
  end

  def setup
    @dist = Dir.mktmpdir("nsis-test")
    @folder = File.join(@dist, "My App-x64-mingw-ucrt")
    [
      Fledge::Entry.file("ruby/bin/ruby.dll", "x" * 3000),
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755),
      Fledge::Entry.file("app/$main.rb", "puts 1\n"),
    ].each { |entry| entry.write_into(@folder) }
  end

  def teardown
    FileUtils.rm_rf(@dist)
  end

  # The installer of the app in @folder, whose files and folders it reads
  # from there.
  def setup_program(identity: self.identity)
    Fledge::Nsis.new(identity:, folder: @folder, to: "#{@folder}-setup.exe")
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
    assert_includes lines, "SetCompressor /SOLID lzma"
    assert_includes lines, "  File /r \"#{Fledge::Nsis.host_path(File.join(@folder, '*'))}\""
    assert_includes lines, "OutFile \"#{Fledge::Nsis.host_path("#{@folder}-setup.exe")}\""
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
    assert_equal ["  Delete \"$INSTDIR\\My App.exe\"", "  Delete \"$INSTDIR\\app\\$$main.rb\"", "  Delete \"$INSTDIR\\ruby\\bin\\ruby.dll\""],
      uninstall.grep(/Delete "\$INSTDIR\\(?!uninstall)/)
    assert_equal ["  RMDir \"$INSTDIR\\ruby\\bin\"", "  RMDir \"$INSTDIR\\app\"", "  RMDir \"$INSTDIR\\ruby\"", "  RMDir $INSTDIR"], uninstall.grep(/RMDir/)
  end

  # Settings' "Installed apps" links a homepage from the uninstall key.
  def test_the_homepage_is_the_uninstall_keys_links
    key = "\"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\com.example.MyApp\""
    refute_match(/URLInfoAbout|HelpLink/, script)
    lines = script(identity: identity(homepage: "https://example.com/$app")).lines.map(&:chomp)
    assert_includes lines, "  WriteRegStr HKCU #{key} \"URLInfoAbout\" \"https://example.com/$$app\""
    assert_includes lines, "  WriteRegStr HKCU #{key} \"HelpLink\" \"https://example.com/$$app\""
  end

  # A license text is Modern UI's license page, before the folder page,
  # read from a file with a byte order mark and DOS line endings; with
  # none there is no such page.
  def test_a_license_is_a_page_before_the_folder
    refute_match(/MUI_PAGE_LICENSE/, script)
    lines = setup_program.script(icon: nil, license: File.join(@dist, "license.txt")).lines.map(&:chomp)
    page = lines.index("!insertmacro MUI_PAGE_LICENSE #{"\"#{Fledge::Nsis.host_path(File.join(@dist, 'license.txt'))}\""}")
    assert page
    assert_equal "!insertmacro MUI_PAGE_DIRECTORY", lines[page.to_i + 1]
    assert_equal "#{Fledge::Nsis::BOM}MIT\r\n\r\nCopyright ©\r\n", Fledge::Nsis.license_text("MIT\n\r\nCopyright ©\n")
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
  # ADR 016: a signed build's installer has makensis sign the uninstaller
  # it writes into it, and then itself, with the signing command, and
  # fail unless it exits 0; an unsigned build's has neither.
  def test_a_signed_installer_and_its_uninstaller_are_signed_as_makensis_writes_them
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "signtool.exe"), "")
      signing = Fledge::WindowsSigning.new("0123456789ABCDEF0123456789ABCDEF01234567", env: { "PATH" => dir })
      text = Fledge::Nsis.new(identity:, folder: @folder, to: "#{@folder}-setup.exe", signing:).script(icon: nil)

      assert_includes text, "\n!uninstfinalize '#{signing.command_line}' = 0\n!finalize '#{signing.command_line}' = 0\n"
      refute_includes script, "finalize"
    end
  end

  # ADR 033: a developer's own command goes to makensis in the first of
  # NSIS's quote characters it does not hold, since NSIS has no escape for
  # a quote inside a string of the same kind.
  def test_a_signing_command_is_quoted_with_a_character_it_does_not_hold
    {
      "sign.cmd" => "'sign.cmd \"%1\"'",
      "pwsh -File 'C:\\sign.ps1' %1" => "`pwsh -File 'C:\\sign.ps1' \"%1\"`",
    }.each do |command, quoted|
      text = Fledge::Nsis.new(identity:, folder: @folder, to: "#{@folder}-setup.exe", signing: Fledge::SignCommand.new(command)).script(icon: nil)

      assert_includes text, "\n!uninstfinalize #{quoted} = 0\n!finalize #{quoted} = 0\n", command
    end
    every = Fledge::Nsis.new(identity:, folder: @folder, to: "#{@folder}-setup.exe", signing: Fledge::SignCommand.new("a 'b' `c`"))
    assert_match(/holds ', ", and ` all/, assert_raises(Fledge::Error) { every.script(icon: nil) }.message)
  end

  def test_names_are_escaped_as_nsis_strings
    text = script(identity: identity(name: "Say \"$1\""))

    assert_includes text, "Name \"Say $\\\"$$1$\\\"\"\n"
  end

  # What the app opens (ADR 032, section 3): a folder, an archive by two
  # extensions (one twice, in another case), and text by its MIME type
  # alone, which Windows does not register.
  def file_associations
    association = Fledge::Config::FileAssociation
    [
      association.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true),
      association.new(name: "Project archive", role: "editor", extensions: %w[zip ZIP fz], mime_types: [], content_types: [], folders: false),
      association.new(name: "Text", role: "viewer", extensions: [], mime_types: ["text/plain"], content_types: [], folders: false),
    ]
  end

  # A ProgID of the app's for each entry with extensions, listed in each
  # extension's OpenWithProgids, so the app is in "Open with" and the
  # extension's default stays the person's; a verb on every folder; and
  # what the uninstaller removes of them.
  def test_the_setup_program_registers_what_the_app_opens_without_taking_a_default
    lines = script(identity: identity(file_associations:)).lines.map(&:chomp)
    install = lines.take_while { |line| line != "Section Uninstall" }
    uninstall = lines.drop_while { |line| line != "Section Uninstall" }
    classes = '"Software\Classes'
    command = %q('"$INSTDIR\My App.exe" "%1"')

    assert_equal [
      %(  WriteRegStr HKCU #{classes}\\Directory\\shell\\com.example.MyApp" "" "Open with My App"),
      %(  WriteRegStr HKCU #{classes}\\Directory\\shell\\com.example.MyApp\\command" "" #{command}),
      %(  WriteRegStr HKCU #{classes}\\com.example.MyApp.2" "" "Project archive"),
      %(  WriteRegStr HKCU #{classes}\\com.example.MyApp.2\\DefaultIcon" "" '"$INSTDIR\\My App.exe",0'),
      %(  WriteRegStr HKCU #{classes}\\com.example.MyApp.2\\shell\\open\\command" "" #{command}),
      %(  WriteRegNone HKCU #{classes}\\.zip\\OpenWithProgids" "com.example.MyApp.2"),
      %(  WriteRegNone HKCU #{classes}\\.fz\\OpenWithProgids" "com.example.MyApp.2"),
      Fledge::Nsis::Script::CHANGE_NOTIFY,
    ], install.grep(/Classes|SHChangeNotify/)
    assert_equal [
      %(  DeleteRegKey HKCU #{classes}\\Directory\\shell\\com.example.MyApp"),
      %(  DeleteRegKey HKCU #{classes}\\com.example.MyApp.2"),
      %(  DeleteRegValue HKCU #{classes}\\.zip\\OpenWithProgids" "com.example.MyApp.2"),
      %(  DeleteRegKey /ifempty HKCU #{classes}\\.zip\\OpenWithProgids"),
      %(  DeleteRegKey /ifempty HKCU #{classes}\\.zip"),
      %(  DeleteRegValue HKCU #{classes}\\.fz\\OpenWithProgids" "com.example.MyApp.2"),
      %(  DeleteRegKey /ifempty HKCU #{classes}\\.fz\\OpenWithProgids"),
      %(  DeleteRegKey /ifempty HKCU #{classes}\\.fz"),
      Fledge::Nsis::Script::CHANGE_NOTIFY,
    ], uninstall.grep(/Classes|SHChangeNotify/)
    assert_empty script.lines.grep(/Classes|SHChangeNotify/), "an app that opens nothing registers nothing"
  end

  def test_a_runtime_without_nsis_is_refused
    Dir.mktmpdir do |dir|
      nsis = Fledge::Nsis.new(identity:, folder: dir, to: File.join(dir, "setup.exe"))

      assert_match(%r{the runtime has no tools/nsis}, assert_raises(Fledge::Error) { nsis.write(nil) }.message)
      assert_match(%r{the runtime has no tools/nsis}, assert_raises(Fledge::Error) { nsis.write(dir) }.message)
    end
  end

  def test_makensis_compiles_the_installer
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    windows = File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.local))
    unless Gem.win_platform? && File.file?(windows)
      flunk "no Windows runtime in #{runtimes}" if ENV["FLEDGE_REQUIRE_RUNTIME"] && Gem.win_platform?
      skip "an NSIS installer is built on Windows, with the Windows runtime's NSIS"
    end

    Dir.mktmpdir do |dir|
      Fledge::Archive.unpack(windows, into: File.join(dir, "runtime"))
      tools = File.join(Dir.glob(File.join(dir, "runtime", "*")).first.to_s, "tools")
      folder = File.join(dir, "My App-x64-mingw-ucrt")
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755).write_into(folder)
      nsis = Fledge::Nsis.new(identity: identity(file_associations:), folder:, to: "#{folder}-setup.exe")

      path = nsis.write(tools)
      assert_equal "MZ", File.binread(path, 2)
      assert_includes File.binread(path), "My App Setup".encode(Encoding::UTF_16LE).b, "its version information names it"
    end
  end
end
