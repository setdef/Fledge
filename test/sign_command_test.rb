# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "support/stand_in_signer"
require "digest"
require "open3"

# Fledge::SignCommand, a Windows app signed by its developer's own
# command (fledge build --sign-command, ADR 033). No agent has a
# certificate in a cloud signing service, so the command is the stand-in
# of test/support/stand_in_signer.rb, which records each path and marks
# each file. On Windows, with a runtime, a whole build runs it as a
# developer would, through fledge build, and CI's Build jobs also run the
# real signtool through --sign-command, which Delivery verifies
# (.github/scripts/deliver-signed.ps1).
class SignCommandTest < Minitest::Test
  BINARIES = File.expand_path("fixtures/binaries", __dir__)
  WINDOWED_APP = File.expand_path("../examples/windowed_app", __dir__)
  EXE = File.expand_path("../exe/fledge", __dir__)
  LIB = File.expand_path("../lib", __dir__)

  # The path, quoted, goes where %1 is, bare or in quotes, as Tauri's
  # signCommand and NSIS's !finalize write it, or after the command.
  def test_the_path_goes_in_place_of_percent_one_or_after_the_command
    path = Fledge::Nsis.host_path("Hello Window/Hello Window.exe")
    {
      "signtool sign /fd sha256 %1" => "signtool sign /fd sha256 \"#{path}\"",
      "signtool sign \"%1\" /v" => "signtool sign \"#{path}\" /v",
      "sign.cmd" => "sign.cmd \"#{path}\"",
      "  sign.cmd  " => "sign.cmd \"#{path}\"",
    }.each do |command, line|
      assert_equal line, Fledge::SignCommand.new(command).line("Hello Window/Hello Window.exe"), command
    end
  end

  # makensis fills in %1 itself, with the uninstaller and then the setup
  # program; Fledge gives it the command with %1 in quotes.
  def test_makensis_gets_the_command_with_percent_one_quoted
    assert_equal 'jsign --alias code "%1"', Fledge::SignCommand.new("jsign --alias code %1").command_line
    assert_equal 'sign.cmd "%1"', Fledge::SignCommand.new("sign.cmd").command_line
  end

  def test_a_blank_command_is_refused
    error = assert_raises(Fledge::Error) { Fledge::SignCommand.new("  ") }
    assert_equal "--sign-command needs a command to run, such as: signtool sign /fd sha256 ... %1", error.message
  end

  def test_signing_selects_the_command_for_windows
    assert_instance_of Fledge::SignCommand, Fledge::Signing.for(Fledge::Platform.find("x64-mingw-ucrt"), nil, command: "sign.cmd")
    assert_instance_of Fledge::SignCommand, Fledge::Signing.for(Fledge::Platform.find("aarch64-mingw-ucrt"), nil, command: "sign.cmd")
  end

  # Once for each PE file, in the order of their paths, and for nothing
  # else: not a text file, nor a Mach-O file with a Windows name.
  def test_each_pe_file_is_signed_once_in_order
    StandInSigner.with do |signer, signed|
      Dir.mktmpdir do |dir|
        folder = app(dir)

        Fledge::SignCommand.new("\"#{signer}\" %1").sign_folder(folder)

        expected = %w[Hello.exe lib/ruby.dll lib/ruby/ext.so].map { |path| Fledge::Nsis.host_path(File.join(folder, path)) }
        assert_equal expected, signed.call
        assert_equal Fledge::WindowsSigning.files(folder).map { |path| Fledge::Nsis.host_path(path) }, expected
        assert File.binread(File.join(folder, "Hello.exe")).end_with?(StandInSigner::MARKER)
        refute File.binread(File.join(folder, "lib/fake.dll")).end_with?(StandInSigner::MARKER)
      end
    end
  end

  # A command that does not exit 0 stops at that file and fails the build
  # naming it, with what the command said, but never the command itself,
  # which may carry a secret (eSigner's CodeSignTool takes a password).
  def test_a_failing_command_names_the_file_and_never_itself
    StandInSigner.with(fail_on: "ruby.dll") do |signer, signed|
      Dir.mktmpdir do |dir|
        folder = app(dir)

        error = assert_raises(Fledge::Error) { Fledge::SignCommand.new("\"#{signer}\" %1 --password=s3cret").sign_folder(folder) }

        failed = Fledge::Nsis.host_path(File.join(folder, "lib/ruby.dll"))
        assert_match(/\Athe signing command failed on #{Regexp.escape(File.join(folder, 'lib/ruby.dll'))} \(.*exit 3\):\n/, error.message)
        assert_includes error.message, "refused #{failed}"
        refute_includes error.message, "s3cret"
        assert_equal 2, signed.call.size, "nothing after the file that failed"
      end
    end
  end

  # A whole build, on Windows, through fledge build as a developer runs
  # it: every PE file of the app, then the uninstaller makensis writes,
  # then the setup program, each once; what the archive holds and the
  # setup program are what was signed, and the checksum is of the signed
  # setup program. FLEDGE_SIGN_COMMAND gives the command as the option
  # would.
  def test_a_windows_build_signs_its_files_then_the_uninstaller_then_the_setup_program
    runtimes = windows_runtimes
    StandInSigner.with do |signer, signed|
      Dir.mktmpdir do |dir|
        out, err, status = fledge(runtimes, dir, { "FLEDGE_SIGN_COMMAND" => "\"#{signer}\" %1" })
        assert_predicate status, :success?, err

        archive, setup = out.lines.map { |line| File.expand_path(line.chomp, dir) }
        folder = archive.delete_suffix(".zip")
        files = Fledge::WindowsSigning.files(folder).map { |path| Fledge::Nsis.host_path(path) }
        *programs, uninstaller, last = signed.call
        assert_equal files, programs
        refute_includes files, uninstaller
        assert_match(/\.tmp\z|uninst/i, uninstaller)
        assert_equal Fledge::Nsis.host_path(setup), last
        assert File.binread(setup).end_with?(StandInSigner::MARKER), "the setup program is the one signed"
        assert_equal Digest::SHA256.file(setup).hexdigest, File.read("#{setup}.sha256").split.first

        Fledge::Archive.unpack(archive, into: File.join(dir, "unpacked"))
        program = File.join(dir, "unpacked", File.basename(folder), "Hello Window.exe")
        assert File.binread(program).end_with?(StandInSigner::MARKER), "the archive holds the signed program"
      end
    end
  end

  # makensis runs the command on the setup program; one that fails there
  # fails the build, naming the setup program.
  def test_a_windows_build_whose_setup_program_will_not_sign_names_it
    runtimes = windows_runtimes
    StandInSigner.with(fail_on: "-setup.exe") do |signer, _|
      Dir.mktmpdir do |dir|
        out, err, status = fledge(runtimes, dir, {}, "--sign-command", "\"#{signer}\" %1")

        assert_equal [1, ""], [status.exitstatus, out]
        assert_includes err, "fledge build: the signing command failed on Hello Window-#{Fledge::Platform.local}-setup.exe (exit 3)"
      end
    end
  end

  # Runs fledge build on examples/windowed_app into +dir+ with +env+ and
  # +arguments+, and returns its output, its errors, and its status.
  private def fledge(runtimes, dir, env, *)
    Open3.capture3({ "FLEDGE_RUNTIME_DIR" => runtimes }.merge(env), RbConfig.ruby, "-I", LIB, EXE, "build", *,
      "-o", File.join(dir, "dist"), WINDOWED_APP, chdir: dir)
  end

  # The folder of runtimes with this Windows computer's, or a skip.
  private def windows_runtimes
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../tmp/runtime", __dir__))
    found = Gem.win_platform? && File.file?(File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.local)))
    return runtimes if found

    flunk "no Windows runtime in #{runtimes}" if ENV["FLEDGE_REQUIRE_RUNTIME"] && Gem.win_platform?
    skip "a Windows app is built on Windows, with a Windows runtime"
  end

  # An app's folder under +dir+: a program, a library, and an extension,
  # each a PE file; a text file; and a Mach-O file named as a library.
  private def app(dir)
    folder = File.join(dir, "Hello-x64-mingw-ucrt")
    FileUtils.mkdir_p(File.join(folder, "lib", "ruby"))
    pe = File.join(BINARIES, Dir.glob("pe-*", base: BINARIES).min.to_s)
    %w[Hello.exe lib/ruby.dll lib/ruby/ext.so].each { |path| FileUtils.cp(pe, File.join(folder, path)) }
    FileUtils.cp(File.join(BINARIES, Dir.glob("macho-*", base: BINARIES).min.to_s), File.join(folder, "lib", "fake.dll"))
    File.write(File.join(folder, "lib", "README.txt"), "not code\n")
    folder
  end
end
