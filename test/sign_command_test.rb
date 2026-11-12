# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"

# Fledge::SignCommand, a Windows app signed by its developer's own
# command (fledge build --sign-command, ADR 051): the command line it
# builds. test/integration/sign_command_signer_test.rb runs the stand-in
# signer of test/support/stand_in_signer.rb on an app's files, and
# test/integration/windows_signed_build_test.rb through a whole build on
# Windows, and CI's Build jobs also run the
# real signtool through --sign-command, which Delivery verifies
# (.github/scripts/deliver-signed.ps1).
class SignCommandTest < Minitest::Test
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
end
