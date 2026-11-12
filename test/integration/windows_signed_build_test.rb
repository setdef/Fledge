# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "../test_helper"
require_relative "../support/stand_in_signer"
require "digest"
require "open3"

# A whole Windows build signed by its developer's own command (fledge
# build --sign-command, ADR 051), on Windows, with the Windows runtime,
# through fledge build as a developer runs it, in a process of its own.
# The command is the stand-in of test/support/stand_in_signer.rb.
# test/sign_command_test.rb covers Fledge::SignCommand itself.
class WindowsSignedBuildTest < Minitest::Test
  WINDOWED_APP = File.expand_path("../../examples/windowed_app", __dir__)
  EXE = File.expand_path("../../exe/fledge", __dir__)
  LIB = File.expand_path("../../lib", __dir__)

  # A whole build, on Windows, through fledge build as a developer runs
  # it: every PE file of the app, then the uninstaller makensis writes,
  # then the setup program, then the MSIX package, each once; what the
  # archive holds and the installers are what was signed, and each
  # checksum is of the signed installer. FLEDGE_SIGN_COMMAND gives the
  # command as the option would.
  def test_a_windows_build_signs_its_files_then_the_uninstaller_then_the_installers
    runtimes = windows_runtimes
    StandInSigner.with do |signer, signed|
      Dir.mktmpdir do |dir|
        out, err, status = fledge(runtimes, dir, { "FLEDGE_SIGN_COMMAND" => "\"#{signer}\" %1" })
        assert_predicate status, :success?, err

        archive, setup, msix = out.lines.map { |line| File.expand_path(line.chomp, dir) }
        folder = archive.delete_suffix(".zip")
        files = Fledge::WindowsSigning.files(folder).map { |path| Fledge::Nsis.host_path(path) }
        *programs, uninstaller, setup_signed, msix_signed = signed.call
        assert_equal files, programs
        refute_includes files, uninstaller
        assert_match(/\.tmp\z|uninst/i, uninstaller)
        assert_equal [Fledge::Nsis.host_path(setup), Fledge::Nsis.host_path(msix)], [setup_signed, msix_signed]
        [setup, msix].each do |installer|
          assert File.binread(installer).end_with?(StandInSigner::MARKER), "#{File.basename(installer)} is the one signed"
          assert_equal Digest::SHA256.file(installer).hexdigest, File.read("#{installer}.sha256").split.first
        end

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
    runtimes = ENV.fetch("FLEDGE_RUNTIME_DIR", File.expand_path("../../tmp/runtime", __dir__))
    found = Gem.win_platform? && File.file?(File.join(runtimes, Fledge::Runtimes.file_name(Fledge::Platform.local)))
    return runtimes if found

    flunk "no Windows runtime in #{runtimes}" if ENV["FLEDGE_REQUIRE_RUNTIME"] && Gem.win_platform?
    skip "a Windows app is built on Windows, with a Windows runtime"
  end
end
