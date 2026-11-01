# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "command"
require_relative "error"
require_relative "nsis"

module Fledge
  # Signs a Windows app with its developer's certificate, through
  # Microsoft's signtool.
  #
  # SmartScreen warns about a program downloaded from the internet that
  # no certificate it trusts has signed, and Smart App Control on Windows
  # 11 checks every program and library a process loads. A developer with
  # a code signing certificate in their certificate store names it by
  # its SHA-1 thumbprint, as signtool's <tt>/sha1</tt> and Briefcase's
  # <tt>--identity</tt> do.
  #
  # This class signs every PE file of an app's folder (its program,
  # Ruby's DLLs and extensions) with SHA-256 and a timestamp, after
  # Fledge has written the program's version information and icon,
  # which a signature seals; and gives makensis the command that signs an
  # NSIS installer and its uninstaller as it writes them.
  #
  # Use it through Fledge::Signing, which <tt>fledge build --sign</tt> calls.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   signing = Fledge::WindowsSigning.new("0123456789ABCDEF0123456789ABCDEF01234567")
  #   signing.sign_folder("dist/Hello-x64-mingw-ucrt")
  #   signing.command_line # => "\"C:\\...\\signtool.exe\" sign /sha1 0123... /fd sha256 ... \"%1\""
  #--
  # SPDX-SnippetEnd
  #++
  class WindowsSigning
    # The timestamp server signtool asks, DigiCert's, as Briefcase's
    # default is: it stamps a signature from any certificate, so the
    # signature stays valid after the certificate expires.
    TIMESTAMP = "http://timestamp.digicert.com"

    # The extensions of the PE files an app holds: programs, libraries,
    # and Ruby's extensions.
    EXTENSIONS = %w[.exe .dll .so].freeze

    # Where signtool comes from.
    INSTALL = "Install the Windows SDK's Signing Tools for Desktop Apps (winget install Microsoft.WindowsSDK.10.0.26100)."

    # Creates the signer for the certificate whose SHA-1 thumbprint is
    # +thumbprint+, finding signtool through +env+. Raises Fledge::Error
    # when +thumbprint+ is not one.
    def initialize(thumbprint, env: ENV)
      unless thumbprint.match?(/\A\h{40}\z/)
        raise Error, "on Windows, --sign takes the SHA-1 thumbprint of a code signing certificate in your certificate " \
          "store, 40 hexadecimal digits, such as (Get-ChildItem Cert:\\CurrentUser\\My -CodeSigningCert).Thumbprint gives; " \
          "#{thumbprint.inspect} is not one"
      end

      @thumbprint = thumbprint.upcase
      @env = env
    end

    # signtool's arguments before the files it signs.
    def arguments
      ["sign", "/sha1", @thumbprint, "/fd", "sha256", "/tr", TIMESTAMP, "/td", "sha256"]
    end

    # Signs every PE file under +folder+.
    def sign_folder(folder)
      files = Signing.code_files(folder, :pe).select { |path| EXTENSIONS.include?(File.extname(path).downcase) }
      tool = WindowsSigning.signtool(@env)
      files.each_slice(50) { |slice| Command.run(tool, *arguments, *slice.map { |path| Nsis.host_path(path) }, install: INSTALL) }
    end

    # The command makensis runs to sign the installer and the uninstaller
    # it writes, with "%1" for the file (NSIS's !finalize and
    # !uninstfinalize).
    def command_line
      ["\"#{Nsis.host_path(WindowsSigning.signtool(@env))}\"", *arguments, "\"%1\""].join(" ")
    end

    # The path of signtool: the first on +env+'s PATH, or else the newest
    # the Windows SDK installed for this computer's architecture. Raises
    # Fledge::Error when there is none.
    def self.signtool(env)
      env["PATH"].to_s.split(File::PATH_SEPARATOR).each do |folder|
        path = File.join(folder, "signtool.exe")
        return path if !folder.empty? && File.file?(path)
      end
      arch = env["PROCESSOR_ARCHITECTURE"].to_s.casecmp?("ARM64") ? "arm64" : "x64"
      kits = File.join(env["ProgramFiles(x86)"].to_s, "Windows Kits", "10", "bin")
      found = Dir.glob("*/#{arch}/signtool.exe", base: kits).max_by { |path| Gem::Version.new(path.split("/").first.to_s) }
      return File.join(kits, found) if found

      raise Error, "fledge build --sign needs signtool, which is on no PATH and in no Windows SDK. #{INSTALL}"
    end
  end
end
