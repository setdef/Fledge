# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "error"
require_relative "nsis"
require_relative "windows_signing"

module Fledge
  # Signs a Windows app with its developer's own signing command.
  #
  # A certificate in Windows' store signs with <tt>fledge build --sign
  # THUMBPRINT</tt> (Fledge::WindowsSigning). One kept in a cloud or a
  # hardware service signs with that service's own tool: Microsoft's
  # Artifact Signing (formerly Trusted Signing) through signtool and its
  # <tt>/dlib</tt> plug-in, DigiCert KeyLocker, SSL.com eSigner, or a key
  # in a cloud KMS through jsign or osslsigncode. Fledge knows none of
  # them; it runs the command the developer gives it, as Tauri's
  # +signCommand+ and electron-builder's +sign+ hook do (ADR 051).
  #
  # This class runs that command once for each PE file Fledge signs, the
  # programs, Ruby's libraries, and its extensions, in the order of
  # their paths, with the file's path, in double quotes, in place of each
  # <tt>%1</tt>, or after the command when it has none; and gives makensis
  # the same command for the uninstaller and the setup program, which
  # NSIS's <tt>!uninstfinalize</tt> and <tt>!finalize</tt> run on each as
  # makensis writes it. The command runs as makensis runs it, through
  # Windows' <tt>cmd.exe</tt>, so it behaves the same for every file. Exit
  # status 0 means signed; anything else fails the build, naming the
  # file and saying what the command printed, but never the command
  # itself, which may hold a secret.
  #
  # Use it through Fledge::Signing, which <tt>fledge build --sign-command</tt>
  # calls.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   signing = Fledge::SignCommand.new("jsign --storetype AZUREKEYVAULT --keystore example --alias code %1")
  #   signing.line("dist/Hello-x64-mingw-ucrt/Hello.exe")
  #   # => "jsign --storetype AZUREKEYVAULT --keystore example --alias code \"C:\\...\\Hello.exe\""
  #   signing.sign_folder("dist/Hello-x64-mingw-ucrt")
  #--
  # SPDX-SnippetEnd
  #++
  class SignCommand
    # What stands for the file's path in the command, as in NSIS's
    # !finalize and Tauri's signCommand; written bare or in double quotes.
    PLACEHOLDER = /"?%1"?/

    # The text before the command that has Windows' cmd.exe run it, as
    # makensis runs a !finalize command (its sane_system, in NSIS's
    # Source/util.cpp): Ruby gives cmd.exe a command line that begins
    # with an internal command (win32/win32.c, is_internal_cmd), and
    # "IF 1==1" keeps cmd.exe from taking the quotes off a command that
    # begins with one.
    CMD = "IF 1==1 "

    # Creates the signer that runs +command+. Raises Fledge::Error when
    # +command+ is blank.
    def initialize(command)
      raise Error, "--sign-command needs a command to run, such as: signtool sign /fd sha256 ... %1" if command.strip.empty?

      @command = command.strip
    end

    # The command line that signs the file at +path+: the command, with
    # the path in double quotes in place of each %1, or after it.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::SignCommand.new("sign.cmd").line("C:/app/Hello.exe") # => "sign.cmd \"C:\\app\\Hello.exe\""
    #--
    # SPDX-SnippetEnd
    #++
    def line(path)
      expand("\"#{Nsis.host_path(path)}\"")
    end

    # Signs every PE file under +folder+ (WindowsSigning.files), one at a
    # time.
    def sign_folder(folder)
      WindowsSigning.files(folder).each { |path| sign(path) }
    end

    # Runs the command on the file at +path+. Raises Fledge::Error, naming
    # the file, when it does not exit 0.
    def sign(path)
      output, status = Open3.capture2e(Gem.win_platform? ? "#{CMD}#{line(path)}" : line(path))
      return if status.success?

      said = output.dup.force_encoding(Encoding::UTF_8).scrub.strip
      raise Error, "the signing command failed on #{path} (#{status})#{":\n#{said}" unless said.empty?}"
    rescue SystemCallError => e
      # The error's message ends with what it ran, the command itself.
      raise Error, "the signing command could not run on #{path} (#{e.message.split(' - ').first})"
    end

    # The command makensis runs to sign the uninstaller and the installer
    # it writes, with "%1", which makensis fills in, for the file.
    def command_line
      expand('"%1"')
    end

    # The command with +quoted+ in place of each %1, or after it.
    private def expand(quoted)
      @command.match?(PLACEHOLDER) ? @command.gsub(PLACEHOLDER) { quoted } : "#{@command} #{quoted}"
    end
  end
end
