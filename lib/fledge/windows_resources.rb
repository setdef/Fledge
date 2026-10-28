# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "version_info"
require_relative "windows_program"

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
  # This module takes the launcher's own resources, keeps its manifest
  # (which makes it aware of long paths and runs it as the person who
  # starts it), replaces any icon and version information with the app's,
  # and writes them back with Fledge::WindowsProgram: an RT_ICON for each
  # of Fledge::Icon#windows_images, an RT_GROUP_ICON numbered ICON_GROUP
  # that lists them, which Windows takes as the program's icon, and an RT_VERSION
  # from Fledge::VersionInfo, all in U.S. English, as a resource compiler
  # writes them by default. A console app gets them too.
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
  #   program = Fledge::WindowsResources.apply(File.binread("launcher.exe"), identity:, file_name: "MyApp.exe")
  #--
  # SPDX-SnippetEnd
  #++
  module WindowsResources
    # The language the resources are written in: U.S. English.
    LANGUAGE = VersionInfo::LANGUAGE

    # The ID of the icon group: IDI_APPLICATION (32512), the ID Tauri gives
    # an app's icon (tauri-build's lib.rs), which a GUI library that asks
    # the program for its application icon by that ID finds. With one
    # group, it is also the one Explorer shows.
    ICON_GROUP = 32_512

    # The launcher +program+, as the program called +file_name+ in an app
    # whose identity is +identity+. Raises Fledge::Error when the program
    # cannot take resources, or the version cannot be a Windows one.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::WindowsResources.apply(launcher, identity:, file_name: "Hello.exe")
    #--
    # SPDX-SnippetEnd
    #++
    def self.apply(program, identity:, file_name:)
      windows = WindowsProgram.new(program)
      replaced = [WindowsProgram::RT_ICON, WindowsProgram::RT_GROUP_ICON, WindowsProgram::RT_VERSION]
      resources = windows.resources.reject { |(type, _, _), _| replaced.include?(type) }
      icon = identity.icon
      icons(icon.windows_images).each { |key, data| resources[key] = data } if icon
      resources[[WindowsProgram::RT_VERSION, 1, LANGUAGE]] = version_info(identity, file_name).bytes
      windows.with_resources(resources)
    end

    # The RT_ICON resources for +images+, numbered from 1, and the
    # RT_GROUP_ICON that lists them: a GRPICONDIR and, for each image, a
    # GRPICONDIRENTRY, whose width and height of 0 mean 256 (Microsoft's
    # "Icons" in the Win32 documentation).
    def self.icons(images)
      resources = {} # : Hash[[Integer, Integer, Integer], String]
      entries = images.each_with_index.map do |(size, data), index|
        resources[[WindowsProgram::RT_ICON, index + 1, LANGUAGE]] = data
        side = (size >= 256) ? 0 : size
        [side, side, 0, 0, 1, 32, data.bytesize, index + 1].pack("CCCCvvVv")
      end
      resources[[WindowsProgram::RT_GROUP_ICON, ICON_GROUP, LANGUAGE]] = [0, 1, images.size].pack("v3") + entries.join
      resources
    end

    # The version information for +identity+: FileDescription, which Task
    # Manager shows, and ProductName and InternalName are its name, and
    # OriginalFilename its program's.
    def self.version_info(identity, file_name)
      VersionInfo.new(version: identity.version, strings: {
        "CompanyName" => identity.publisher.to_s,
        "FileDescription" => identity.name,
        "FileVersion" => identity.version,
        "InternalName" => identity.name,
        "LegalCopyright" => identity.copyright.to_s,
        "OriginalFilename" => file_name,
        "ProductName" => identity.name,
        "ProductVersion" => identity.version,
      })
    end
  end
end
