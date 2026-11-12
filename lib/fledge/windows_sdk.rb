# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "rubygems"
require_relative "error"

module Fledge
  # Finds a tool of Microsoft's Windows SDK on the computer that builds
  # a Windows app: signtool, which signs it (Fledge::WindowsSigning), and
  # MakeAppx, which packs its MSIX package (Fledge::Msix).
  #
  # Fledge carries neither. Microsoft lets them be redistributed only
  # under the Windows SDK's own license terms, so a developer gets them
  # from Microsoft: the Windows SDK's installer puts them in
  # <tt>C:\Program Files (x86)\Windows Kits\10\bin\VERSION\ARCH</tt>,
  # where GitHub's Windows runners have them, and Microsoft's
  # Microsoft.Windows.SDK.BuildTools package holds the same folder, for
  # a computer with no SDK installed, whose folder a developer puts on
  # +PATH+. A tool on +PATH+ comes first, so the developer chooses.
  #
  # Use it through Fledge::WindowsSigning and Fledge::Msix.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::WindowsSdk.tool("makeappx.exe", ENV, needed_by: "an msix installer")
  #   # => "C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/makeappx.exe"
  #--
  # SPDX-SnippetEnd
  #++
  module WindowsSdk
    # Where the tools come from.
    INSTALL = "Install the Windows SDK (winget install Microsoft.WindowsSDK.10.0.26100), or put the folder of " \
      "Microsoft's Microsoft.Windows.SDK.BuildTools package that holds it for this computer, bin\\VERSION\\x64 or arm64, on PATH."

    # The path of the tool +file+, such as <tt>signtool.exe</tt>: the first
    # on +env+'s PATH, or else the newest the Windows SDK installed for
    # this computer's architecture. Raises Fledge::Error, saying what it
    # is +needed_by+ and how to install it, when there is none.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsSdk.tool("signtool.exe", { "PATH" => "C:/sdk/bin" }, needed_by: "--sign")
    #   # => "C:/sdk/bin/signtool.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def self.tool(file, env, needed_by:)
      env["PATH"].to_s.split(File::PATH_SEPARATOR).each do |folder|
        path = File.join(folder, file)
        return path if !folder.empty? && File.file?(path)
      end
      arch = env["PROCESSOR_ARCHITECTURE"].to_s.casecmp?("ARM64") ? "arm64" : "x64"
      kits = File.join(env["ProgramFiles(x86)"].to_s, "Windows Kits", "10", "bin")
      found = Dir.glob("*/#{arch}/#{file}", base: kits).max_by { |path| Gem::Version.new(path.split("/").first.to_s) }
      return File.join(kits, found) if found

      raise Error, "#{needed_by} needs #{File.basename(file, '.exe')}, which is on no PATH and in no Windows SDK. #{INSTALL}"
    end
  end
end
