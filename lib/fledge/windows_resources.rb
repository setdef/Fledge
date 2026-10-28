# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tmpdir"
require_relative "command"
require_relative "error"

module Fledge
  # Puts an app's identity into its Windows program: its icon and its
  # version information.
  #
  # Explorer, the taskbar, Alt-Tab, and a shortcut show a program's first
  # icon group; Task Manager shows its FileDescription; a Properties
  # dialog shows its ProductName, CompanyName, versions, and copyright
  # (decision 18). Without them, every app built with Fledge would show
  # the launcher's blank icon and its bare file name.
  #
  # This module has rcedit write them, as electron-builder and
  # electron-packager have it write an Electron app's: Electron's own
  # resource editor (MIT), which calls Windows' UpdateResource, so it
  # runs on Windows, where each Windows app is built (ADR 010). The
  # Windows runtime carries a pinned build of it in its +tools+ folder,
  # which no app holds. It sets FileDescription, ProductName, and
  # InternalName to the app's name, OriginalFilename to its program's,
  # CompanyName and LegalCopyright when there are a publisher and a
  # copyright, FileVersion and ProductVersion to the version as written,
  # whose leading numbers rcedit makes FILEVERSION and PRODUCTVERSION,
  # and the icon. rcedit keeps the launcher's manifest, which makes it
  # aware of long paths and runs it as the person who starts it. A
  # console app gets them too.
  #
  # Use it through Fledge::Assembly.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   identity = Fledge::App.at("my_app").identity
  #   Fledge::WindowsResources.apply("dist/MyApp-x64-mingw-ucrt/MyApp.exe", identity:, tools: "/tmp/runtime/tools")
  #--
  # SPDX-SnippetEnd
  #++
  module WindowsResources
    # rcedit's name in the Windows runtime's +tools+ folder.
    RCEDIT = "rcedit.exe"

    # The largest part a Windows version number holds: 16 bits.
    MAX_PART = 65_535

    # Writes the identity +identity+ into the Windows program at +program+
    # with the rcedit in +tools+, the runtime's tools folder. Raises
    # Fledge::Error when the runtime has no rcedit, the version cannot be
    # a Windows one, or rcedit fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsResources.apply("dist/Hello-x64-mingw-ucrt/Hello.exe", identity:, tools:)
    #--
    # SPDX-SnippetEnd
    #++
    def self.apply(program, identity:, tools:)
      rcedit = tools && File.join(tools, RCEDIT)
      raise Error, "the runtime has no tools/#{RCEDIT}, which Windows runtimes carry from Fledge 0.0.1.pre.8 on" unless rcedit && File.file?(rcedit)

      numbers(identity.version)
      arguments = strings(identity, File.basename(program)).flat_map { |key, value| ["--set-version-string", key, value] }
      arguments += ["--set-file-version", identity.version, "--set-product-version", identity.version]
      icon = identity.icon
      arguments += ["--set-icon", icon.file("ico")] if icon
      Command.run(rcedit, program, *arguments, install: "Windows runtimes from Fledge 0.0.1.pre.8 on carry it.")
    end

    # The version information's strings for +identity+, whose program is
    # +file_name+: FileDescription, which Task Manager shows, and
    # ProductName and InternalName are its name, and OriginalFilename its
    # program's.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsResources.strings(identity, "Hello.exe")["OriginalFilename"] # => "Hello.exe"
    #--
    # SPDX-SnippetEnd
    #++
    def self.strings(identity, file_name)
      {
        "CompanyName" => identity.publisher,
        "FileDescription" => identity.name,
        "InternalName" => identity.name,
        "LegalCopyright" => identity.copyright,
        "OriginalFilename" => file_name,
        "ProductName" => identity.name,
      }.compact
    end

    # The four numbers of a Windows version, FILEVERSION's and
    # VIProductVersion's, from +version+: its leading numbers, at most
    # four, padded with zeros. Raises Fledge::Error when it begins with no
    # number or a part is larger than MAX_PART.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsResources.numbers("1.2.3.pre.4") # => [1, 2, 3, 0]
    #--
    # SPDX-SnippetEnd
    #++
    def self.numbers(version)
      parts = version.split(".").take_while { |part| part.match?(/\A\d+\z/) }.first(4).map(&:to_i)
      raise Error, "the version #{version} does not begin with a number" if parts.empty?

      too_large = parts.find { |part| part > MAX_PART }
      raise Error, "the version #{version} has a part, #{too_large}, larger than Windows' version numbers hold (#{MAX_PART})" if too_large

      parts.fill(0, (parts.size)...4)
    end
  end
end
