# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "app_image"
require_relative "config"
require_relative "dmg"
require_relative "nsis"

module Fledge
  # Which installers <tt>fledge build</tt> writes for an app, and where.
  #
  # Tauri's bundler builds, by default, every installer the platform it
  # builds for has (<tt>bundle.targets: "all"</tt>), and so does Fledge
  # (ADR 009): a windowed app gets, beside each archive, a disk image for
  # macOS, an NSIS setup program for Windows, and an AppImage for Linux,
  # unless <tt>fledge.yml</tt> lists the ones it wants under +installers+,
  # or none (<tt>installers: []</tt>). A console app gets none: a terminal
  # tool is installed by putting its program on a +PATH+, which a disk
  # image's drag, a Start menu shortcut, and an AppImage all leave undone.
  #
  # This module chooses each target's installers and makes the object
  # that writes each one (Fledge::Dmg, Fledge::Nsis, Fledge::AppImage),
  # named after the archive: <tt>NAME-PLATFORM.dmg</tt>,
  # <tt>NAME-PLATFORM-setup.exe</tt> (as Tauri ends an NSIS installer's
  # name), and <tt>NAME-PLATFORM.AppImage</tt>.
  #
  # Use it through Fledge::Assembly and <tt>fledge build</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   app = Fledge::App.at("examples/windowed_app")
  #   Fledge::Installers.formats(app, Fledge::Platform.find("x64-mingw-ucrt")) # => ["nsis"]
  #   Fledge::Installers.file_name("nsis", "Hello Window-x64-mingw-ucrt")    # => "Hello Window-x64-mingw-ucrt-setup.exe"
  #--
  # SPDX-SnippetEnd
  #++
  module Installers
    # The operating system each installer is for.
    OS = { "dmg" => "darwin", "nsis" => "windows", "appimage" => "linux" }.freeze

    # What follows an archive's base name in each installer's name.
    SUFFIX = { "dmg" => ".dmg", "nsis" => "-setup.exe", "appimage" => ".AppImage" }.freeze

    # The installers +app+ gets for +platform+: those its
    # <tt>fledge.yml</tt> lists, or every one, for a windowed app, that is
    # for the platform's operating system.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.formats(Fledge::App.at("examples/hello"), Fledge::Platform.local) # => []
    #--
    # SPDX-SnippetEnd
    #++
    def self.formats(app, platform)
      return [] unless app.identity.windowed?

      (app.config.installers || Config::INSTALLERS).select { |format| OS.fetch(format) == platform.os }
    end

    # The file name of the +format+ installer of the archive whose base
    # name is +base+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.file_name("dmg", "MyApp-arm64-darwin") # => "MyApp-arm64-darwin.dmg"
    #--
    # SPDX-SnippetEnd
    #++
    def self.file_name(format, base)
      "#{base}#{SUFFIX.fetch(format)}"
    end

    # The object that writes +app+'s +format+ installer, whose built
    # folder is +folder+, into the folder +out+.
    #
    # [makensis] The NSIS compiler, which an NSIS installer needs.
    # [mtime] When everything in it was made, as Unix time.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.writer("dmg", app:, folder: "dist/MyApp-arm64-darwin", makensis: nil)
    #   # => a Fledge::Dmg writing dist/MyApp-arm64-darwin.dmg
    #--
    # SPDX-SnippetEnd
    #++
    def self.writer(format, app:, folder:, makensis:, mtime: Time.now.to_i)
      to = file_name(format, folder)
      identity = app.identity
      case format
      when "dmg" then Dmg.new(name: identity.name, to:, mtime:)
      when "appimage" then AppImage.new(identity:, to:, mtime:)
      else
        raise Error, "an NSIS installer needs makensis, which fledge build could not find" unless makensis

        Nsis.new(identity:, folder:, to:, makensis:)
      end
    end
  end
end
