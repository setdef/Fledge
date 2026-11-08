# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "app_image"
require_relative "config"
require_relative "deb"
require_relative "dmg"
require_relative "nsis"
require_relative "signing"

module Fledge
  # Which installers <tt>fledge build</tt> writes for an app, and where.
  #
  # Tauri's bundler builds, by default, every installer the platform it
  # builds for has (<tt>bundle.targets: "all"</tt>), and so does Fledge
  # (ADR 009): a windowed app gets, beside each archive, a disk image for
  # macOS, an NSIS setup program for Windows, and an AppImage for Linux,
  # and a <tt>.deb</tt> for Debian and Ubuntu when <tt>fledge.yml</tt> asks
  # for one, since not every Linux computer has dpkg-deb (ADR 021),
  # unless <tt>fledge.yml</tt> lists the ones it wants under +installers+,
  # or none (<tt>installers: []</tt>). A console app gets none: a terminal
  # tool is installed by putting its program on a +PATH+, which a disk
  # image's drag, a Start menu shortcut, and an AppImage all leave undone.
  #
  # This module chooses each target's installers and writes each one
  # from the built app's folder (Fledge::Dmg, Fledge::Nsis,
  # Fledge::AppImage, Fledge::Deb), named after the archive: <tt>NAME-PLATFORM.dmg</tt>,
  # <tt>NAME-PLATFORM-setup.exe</tt> (as Tauri ends an NSIS installer's
  # name), <tt>NAME-PLATFORM.AppImage</tt>, and <tt>NAME-PLATFORM.deb</tt>.
  #
  # Use it through Fledge::Assembly and <tt>fledge build</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    OS = { "dmg" => "darwin", "nsis" => "windows", "appimage" => "linux", "deb" => "linux" }.freeze

    # What follows an archive's base name in each installer's name.
    SUFFIX = { "dmg" => ".dmg", "nsis" => "-setup.exe", "appimage" => ".AppImage", "deb" => ".deb" }.freeze

    # The installers +app+ gets for +platform+: those its
    # <tt>fledge.yml</tt> lists, or Config::DEFAULT_INSTALLERS, for a
    # windowed app, that are for the platform's operating system. A
    # +deb+ is for Debian and Ubuntu, which have glibc, so a musl platform
    # gets none, as a Mac gets no setup program from the same list.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.formats(Fledge::App.at("examples/hello"), Fledge::Platform.local) # => []
    #--
    # SPDX-SnippetEnd
    #++
    def self.formats(app, platform)
      return [] unless app.identity.windowed?

      (app.config.installers || Config::DEFAULT_INSTALLERS).select do |format|
        OS.fetch(format) == platform.os && (format != "deb" || Deb::ARCHITECTURES.key?(platform.name))
      end
    end

    # The file name of the +format+ installer of the archive whose base
    # name is +base+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.file_name("dmg", "MyApp-arm64-darwin") # => "MyApp-arm64-darwin.dmg"
    #--
    # SPDX-SnippetEnd
    #++
    def self.file_name(format, base)
      "#{base}#{SUFFIX.fetch(format)}"
    end

    # Writes every installer +app+ gets on +platform+ (Installers.formats)
    # from its built folder +folder+, and returns their paths.
    def self.write_all(app, platform, folder:, tools:, signing: nil)
      formats(app, platform).map { |format| write(format, app:, folder:, platform:, tools:, signing:) }
    end

    # Writes +app+'s +format+ installer from its built folder +folder+,
    # beside it, and returns its path.
    #
    # [platform] The Fledge::Platform the app is built for.
    # [tools] The runtime's tools folder, or +nil+ when it has none.
    # [signing] The signer that signs the installer (Fledge::Signing.for),
    #           or +nil+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.write("dmg", app:, folder: "dist/MyApp-arm64-darwin", platform:, tools: nil)
    #   # => "dist/MyApp-arm64-darwin.dmg"
    #--
    # SPDX-SnippetEnd
    #++
    def self.write(format, app:, folder:, platform:, tools:, signing: nil)
      to = file_name(format, folder)
      identity = app.identity
      case format
      when "dmg" then Dmg.write(File.join(folder, "#{identity.name}.app"), name: identity.name, to:, signing: (signing if signing.is_a?(MacSigning)))
      when "appimage" then AppImage.write(identity:, folder:, tools:, to:)
      when "deb" then deb(app, folder:, platform:, to:)
      else Nsis.new(identity:, folder:, to:, signing: (signing.is_a?(MacSigning) ? nil : signing), license: license(app)).write(tools)
      end
    end

    # Writes +app+'s <tt>.deb</tt>, with its license text and changelog.
    private_class_method def self.deb(app, folder:, platform:, to:)
      changelog = app.config.linux&.deb_changelog
      Deb.write(identity: app.identity, folder:, platform:, to:, system_libraries: app.config.system_libraries(platform.os),
        license: license(app), changelog: changelog && project_file(app, changelog, "linux: deb_changelog"))
    end

    # The text of +app+'s <tt>license_file</tt>, or +nil+ when it names
    # none. Raises Fledge::Error when it is missing or not UTF-8, which a
    # <tt>.deb</tt>'s copyright file must be (Debian Policy 12.5).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Installers.license(Fledge::App.at("examples/windowed_app")).lines.first # => "MIT No Attribution\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.license(app)
      name = app.config.license_file
      return nil unless name

      text = File.binread(project_file(app, name, "license_file")).force_encoding(Encoding::UTF_8).delete_prefix(Nsis::BOM)
      raise Error, "#{File.join(app.root, Config::FILE)}: license_file names #{name}, which is not UTF-8 text. Save it as UTF-8." unless text.valid_encoding?

      text
    end

    # The path of the file +name+ in +app+'s project, which +key+ of its
    # <tt>fledge.yml</tt> names. Raises Fledge::Error when it is no file.
    private_class_method def self.project_file(app, name, key)
      path = File.join(app.root, name)
      return path if File.file?(path)

      raise Error, "#{File.join(app.root, Config::FILE)}: #{key} names #{name}, which is not a file in #{app.root}"
    end
  end
end
