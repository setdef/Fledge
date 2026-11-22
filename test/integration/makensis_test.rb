# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/loopback_server"

# The installer that the Windows runtime's makensis compiles from the
# script Fledge::Nsis writes, on Windows, where FLEDGE_RUNTIME_DIR holds
# the Windows runtime (as CI's Windows test jobs do).
# test/nsis_test.rb covers the script.
class MakensisTest < Minitest::Test
  def identity(file_associations: [], name: "My App", identifier: "com.example.MyApp")
    Fledge::Identity.new(name:, kind: "windowed", identifier:, version: "1.2.3.pre.4",
      publisher: "Example, Inc.", copyright: "© 2026 Example, Inc.", icon: nil, description: nil, long_description: nil,
      homepage: nil, file_associations:)
  end

  # What the app opens: a folder, an archive by two extensions
  # (one twice, in another case), and text by its MIME type alone, which
  # Windows does not register.
  def file_associations
    association = Fledge::Config::FileAssociation
    [
      association.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true, defines_type: false),
      association.new(name: "Project archive", role: "editor", extensions: %w[zip ZIP fz], mime_types: [], content_types: [], folders: false, defines_type: false),
      association.new(name: "Text", role: "viewer", extensions: [], mime_types: ["text/plain"], content_types: [], folders: false, defines_type: false),
    ]
  end

  # Yields a temporary folder and the tools folder of the Windows
  # runtime unpacked in it.
  def with_tools
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    windows = File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.local))
    unless Gem.win_platform? && File.file?(windows)
      flunk "no Windows runtime in #{runtimes}" if ENV["FLEDGE_REQUIRE_RUNTIME"] && Gem.win_platform?
      skip "an NSIS installer is built on Windows, with the Windows runtime's NSIS"
    end

    Dir.mktmpdir do |dir|
      Fledge::Archive.unpack(windows, into: File.join(dir, "runtime"))
      yield dir, File.join(Dir.glob(File.join(dir, "runtime", "*")).first.to_s, "tools")
    end
  end

  def test_makensis_compiles_the_installer
    with_tools do |dir, tools|
      folder = File.join(dir, "My App-x64-mingw-ucrt")
      Fledge::Entry.file("My App.exe", "MZ", mode: 0o755).write_into(folder)
      nsis = Fledge::Nsis.new(identity: identity(file_associations:), folder:, platform: Fledge::Platform.local, to: "#{folder}-setup.exe")

      path = nsis.write(tools)
      assert_equal "MZ", File.binread(path, 2)
      assert_includes File.binread(path), "My App Setup".encode(Encoding::UTF_16LE).b, "its version information names it"
    end
  end

  # A stand-in for Microsoft's Redistributable, compiled by the
  # runtime's makensis: a silent program that writes the arguments it
  # was run with to the file FLEDGE_STAND_IN_LOG names, and installs
  # nothing.
  def stand_in_installer(dir, tools)
    script = File.join(dir, "stand-in.nsi")
    program = File.join(dir, "stand-in.exe")
    File.write(script, <<~NSIS)
      Unicode true
      RequestExecutionLevel user
      SilentInstall silent
      OutFile "#{Fledge::Nsis.host_path(program)}"
      !include FileFunc.nsh
      Section
        ${GetParameters} $0
        ReadEnvStr $2 FLEDGE_STAND_IN_LOG
        FileOpen $1 $2 w
        FileWrite $1 $0
        FileClose $1
      SectionEnd
    NSIS
    nsis = File.join(tools, "nsis")
    output, status = Open3.capture2e({ "NSISDIR" => Fledge::Nsis.host_path(nsis) }, File.join(nsis, Fledge::Nsis::MAKENSIS), "-V2", "-NOCONFIG",
      Fledge::Nsis.host_path(script))
    assert status.success?, output
    premise = File.join(dir, "premise.log")
    _, ran = Open3.capture2e({ "FLEDGE_STAND_IN_LOG" => Fledge::Nsis.host_path(premise) }, program, "/install", "/quiet", "/norestart")
    assert_equal [0, "/install /quiet /norestart"], [ran.exitstatus, File.file?(premise) && File.read(premise).strip], "the stand-in, run by itself, logs how it ran"
    File.binread(program)
  end

  # The setup program of an app built with windows: { visual_c_runtime:
  # central } whose launcher looks for the DLLs +names+, downloading the
  # Redistributable from +server+, and how it ran, installed silently,
  # as the person who runs it, into a folder of the test's own.
  def install_assuming(names, dir:, tools:, server:)
    folder = File.join(dir, "Fledge VC Test-x64-mingw-ucrt")
    Fledge::Entry.file("Fledge VC Test.exe", "MZ", mode: 0o755).write_into(folder)
    Fledge::Entry.file("fledge.cfg", "entry = main.rb\nvisual_c_runtime = #{names}\n").write_into(folder)
    setup = Fledge::Nsis.new(identity: identity(name: "Fledge VC Test", identifier: "com.example.FledgeVisualCTest"), folder:,
      platform: Fledge::Platform.local, to: "#{folder}-setup.exe", redistributable: server.url("/vc_redist.x64.exe")).write(tools)
    temporary = Fledge::Nsis.host_path(File.join(dir, "temp"))
    FileUtils.mkdir_p(temporary)
    env = { "FLEDGE_STAND_IN_LOG" => Fledge::Nsis.host_path(File.join(dir, "stand-in.log")), "TEMP" => temporary, "TMP" => temporary }
    _, status = Open3.capture2e(env, setup, "/S", "/D=#{Fledge::Nsis.host_path(File.join(dir, 'installed'))}")
    status
  end

  # With visual_c_runtime: central, a setup program on a computer whose
  # System32 lacks a DLL the app needs downloads the Redistributable from
  # its link and runs it quietly; when the DLL is still missing after
  # that, a silent install aborts, before it installs anything. A
  # loopback server stands in for Microsoft's link, and the DLL is one no
  # computer has.
  def test_a_setup_program_runs_the_redistributable_it_downloads_and_aborts_while_a_dll_is_missing
    with_tools do |dir, tools|
      server = LoopbackServer.new("/vc_redist.x64.exe" => [200, { "Cache-Control" => "no-store" }, stand_in_installer(dir, tools)])
      begin
        status = install_assuming("fledge-absent140.dll", dir:, tools:, server:)
      ensure
        server.stop
      end

      log = File.join(dir, "stand-in.log")
      ran = File.file?(log) && File.read(log).strip
      facts = "requests #{server.requests.inspect}, setup exit #{status.exitstatus}, stand-in log #{ran.inspect}, " \
        "installed #{File.exist?(File.join(dir, 'installed'))}"

      assert_equal ["/vc_redist.x64.exe"], server.requests, facts
      assert_equal "/install /quiet /norestart", ran, facts
      assert_equal 2, status.exitstatus, "NSIS's status for an install its script aborted: #{facts}"
      refute_path_exists File.join(dir, "installed"), facts
    end
  end
end
