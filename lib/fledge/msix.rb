# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "tmpdir"
require_relative "command"
require_relative "config"
require_relative "error"
require_relative "nsis"
require_relative "windows_resources"
require_relative "windows_sdk"

module Fledge
  # A Windows app's MSIX package, which the Microsoft Store takes, made
  # by Microsoft's MakeAppx from the built app's folder.
  #
  # The Store re-signs an MSIX package with Microsoft's own certificate
  # once the app passes certification, so a developer who ships through
  # the Store needs no code signing certificate of their own (Microsoft
  # Learn, "App package requirements for MSIX app", "Code signing for
  # Microsoft Store submissions"); an EXE or MSI installer submitted to
  # the Store must be signed by its developer. Windows installs a package
  # outside the Store only when a certificate the computer trusts has
  # signed it, so with <tt>--sign</tt> or <tt>--sign-command</tt> the
  # package is signed as the setup program is, and without them it is
  # left unsigned, for the Store.
  #
  # This class writes the package's manifest, <tt>AppxManifest.xml</tt>,
  # from the app's identity, as Microsoft's "Generating MSIX package
  # components" describes a desktop app's: a full-trust app
  # (<tt>runFullTrust</tt>, <tt>Windows.FullTrustApplication</tt>) for
  # <tt>Windows.Desktop</tt>, whose identity is +windows+'s
  # +msix_name+, or the identifier, and +msix_publisher+
  # (Config::Windows), and whose version is the app's first three
  # numbers and a 0, the fourth part the Store keeps for itself. Its
  # logos are the developer's own PNGs (Icon::MSIX), and each extension
  # the app opens is a file type association, which lists the app in
  # the extension's "Open with" and never makes it the default (ADR 052).
  # MakeAppx packs the folder through a mapping file, with that manifest,
  # the logos, and the app's <tt>fledge.cfg</tt> with no identifier: in a
  # package the app is known by the package's own AppUserModelID, which
  # the identifier made the process's own would override, as Microsoft's
  # "Application User Model IDs" says of an app a deployment framework
  # manages.
  #
  # MakeAppx is the Windows SDK's (Fledge::WindowsSdk).
  #
  # Use it through Fledge::Installers.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   Fledge::Msix.new(identity:, windows:, folder: "dist/MyApp-x64-mingw-ucrt", platform:,
  #     to: "dist/MyApp-x64-mingw-ucrt.msix").write # => "dist/MyApp-x64-mingw-ucrt.msix"
  #--
  # SPDX-SnippetEnd
  #++
  class Msix
    # The package's processor architecture for each Windows platform.
    ARCHITECTURES = { "x64-mingw-ucrt" => "x64", "aarch64-mingw-ucrt" => "arm64" }.freeze

    # The oldest Windows the package installs on: Windows 10 1809, which
    # electron-builder's MSIX target takes as its default, and the Store's
    # minimum (electron-builder's website/docs/msix.md, "Version
    # Targeting"). A manifest with EntryPoint, not uap10's
    # RuntimeBehavior, installs there (Microsoft Learn, "Generating MSIX
    # package components").
    MIN_VERSION = "10.0.17763.0"

    # The newest Windows the package was tested on: Windows 11 24H2.
    MAX_VERSION_TESTED = "10.0.26100.0"

    # The folder in the package that holds the logos.
    ASSETS = "Assets"

    # The application's ID in the package, which its AppUserModelID,
    # <tt>PACKAGE_FAMILY_NAME!App</tt>, ends with, as Visual Studio names a
    # package's one application.
    APPLICATION = "App"

    # The file in the app's folder that says what its program runs.
    CONFIG = "fledge.cfg"

    # The namespaces of the manifest's elements.
    NAMESPACES = {
      "xmlns" => "http://schemas.microsoft.com/appx/manifest/foundation/windows10",
      "xmlns:uap" => "http://schemas.microsoft.com/appx/manifest/uap/windows10",
      "xmlns:rescap" => "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities",
    }.freeze

    # Creates the package of the app whose identity is +identity+ and
    # whose built folder is +folder+, to be written to +to+.
    #
    # [windows] The app's Config::Windows, which names the package's
    #           publisher.
    # [platform] The Fledge::Platform the app is built for.
    # [signing] The signer that signs the package once it is written
    #           (Fledge::WindowsSigning or Fledge::SignCommand), or +nil+.
    # [env] The environment to find MakeAppx through.
    def initialize(identity:, windows:, folder:, platform:, to:, signing: nil, env: ENV)
      @identity = identity
      @windows = windows
      @folder = folder
      @platform = platform
      @to = to
      @signing = signing
      @env = env
    end

    # Writes the package with MakeAppx, signs it when there is a signer,
    # and returns its path. Raises Fledge::Error when the identity cannot
    # make a package, when MakeAppx is missing or fails, or when signing
    # fails.
    def write
      text = manifest
      makeappx = WindowsSdk.tool("makeappx.exe", @env, needed_by: "an msix installer")
      Dir.mktmpdir("fledge-msix") do |work|
        File.binwrite(File.join(work, "AppxManifest.xml"), text)
        File.binwrite(File.join(work, CONFIG), Msix.packaged_config(File.binread(File.join(@folder, CONFIG))))
        File.binwrite(File.join(work, "mapping.txt"), mapping(work))
        FileUtils.rm_f(@to)
        Command.run(makeappx, "pack", "/o", "/h", "SHA256", "/f", Nsis.host_path(File.join(work, "mapping.txt")), "/p", Nsis.host_path(@to),
          install: WindowsSdk::INSTALL)
      end
      @signing&.sign(@to)
      @to
    rescue Error
      FileUtils.rm_f(@to)
      raise
    end

    # The package's manifest, <tt>AppxManifest.xml</tt>. Raises
    # Fledge::Error when the app has no icon or publisher, or a name a
    # package cannot have.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   msix.manifest[/<Identity [^>]*>/]
    #   # => "<Identity Name=\"com.example.MyApp\" Publisher=\"CN=Example\" Version=\"1.2.3.0\" ProcessorArchitecture=\"x64\" />"
    #--
    # SPDX-SnippetEnd
    #++
    def manifest
      logos
      description = @identity.description || @identity.name
      [
        %(<?xml version="1.0" encoding="utf-8"?>),
        "<Package #{attributes(NAMESPACES.merge('IgnorableNamespaces' => 'uap rescap'))}>",
        "  <Identity #{attributes('Name' => package_name, 'Publisher' => publisher, 'Version' => version, 'ProcessorArchitecture' => architecture)} />",
        "  <Properties>",
        "    <DisplayName>#{xml(@identity.name)}</DisplayName>",
        "    <PublisherDisplayName>#{xml(publisher_display_name)}</PublisherDisplayName>",
        "    <Description>#{xml(description)}</Description>",
        "    <Logo>#{logo('StoreLogo')}</Logo>",
        "  </Properties>",
        "  <Resources>",
        %(    <Resource Language="en-us" />),
        "  </Resources>",
        "  <Dependencies>",
        %(    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="#{MIN_VERSION}" MaxVersionTested="#{MAX_VERSION_TESTED}" />),
        "  </Dependencies>",
        "  <Capabilities>",
        %(    <rescap:Capability Name="runFullTrust" />),
        "  </Capabilities>",
        "  <Applications>",
        "    <Application #{attributes('Id' => APPLICATION, 'Executable' => "#{@identity.name}.exe", 'EntryPoint' => 'Windows.FullTrustApplication')}>",
        "      <uap:VisualElements #{attributes('DisplayName' => @identity.name, 'Description' => description, 'BackgroundColor' => 'transparent',
          'Square150x150Logo' => logo('Square150x150Logo'), 'Square44x44Logo' => logo('Square44x44Logo'))} />",
        *extensions,
        "    </Application>",
        "  </Applications>",
        "</Package>",
        "",
      ].join("\r\n")
    end

    # MakeAppx's mapping file: every file of the app's folder at its path
    # in the package, but <tt>fledge.cfg</tt>, which is +work+'s, with
    # the manifest and the logos.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   msix.mapping("C:/Temp/work").lines.first(2)
    #   # => ["[Files]\r\n", "\"C:\\Temp\\work\\AppxManifest.xml\" \"AppxManifest.xml\"\r\n"]
    #--
    # SPDX-SnippetEnd
    #++
    def mapping(work)
      files = Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder).sort.select do |path|
        path != CONFIG && File.file?(File.join(@folder, path))
      end
      inside = { "AppxManifest.xml" => File.join(work, "AppxManifest.xml"), CONFIG => File.join(work, CONFIG) }
      logos.each { |name, path| inside["#{ASSETS}/#{name}.png"] = path }
      files.each { |path| inside[path] = File.join(@folder, path) }
      lines = inside.map { |to, from| %("#{Nsis.host_path(from)}" "#{to.tr('/', '\\')}") }
      ["[Files]", *lines, ""].join("\r\n")
    end

    # The text of +config+, a <tt>fledge.cfg</tt>, without its
    # identifiers, so that the launcher in a package leaves the process
    # the package's AppUserModelID.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::Msix.packaged_config("entry = main.rb\nidentifier = com.example.A\n") # => "entry = main.rb\n"
    #--
    # SPDX-SnippetEnd
    #++
    def self.packaged_config(config)
      config.gsub(/^identifier = [^\n]*\n/, "")
    end

    # The package's name: +msix_name+, or else the identifier. Raises
    # Fledge::Error when the identifier cannot be one.
    private def package_name
      name = @windows&.msix_name || @identity.identifier.to_s
      return name if name.match?(Config::Windows::NAME)

      raise Error, "the identifier #{name} cannot name an MSIX package, whose name is 3 to 50 letters, digits, periods, and hyphens; " \
        "give fledge.yml's windows an msix_name, such as Partner Center's Package/Identity/Name"
    end

    # The package's publisher, +msix_publisher+. Raises Fledge::Error when
    # there is none.
    private def publisher
      @windows&.msix_publisher || raise(Error, "an msix installer needs fledge.yml's windows: msix_publisher, such as CN=Example")
    end

    # The publisher's name as people see it: the app's publisher, which
    # Partner Center's Package/Properties/PublisherDisplayName must match.
    private def publisher_display_name
      @identity.publisher || raise(Error, "an msix installer needs a publisher to show, which fledge.yml's publisher or the gemspec's authors give")
    end

    # The package's version: the app's first three numbers and a 0.
    private def version
      [*WindowsResources.numbers(@identity.version).first(3), 0].join(".")
    end

    # The package's processor architecture.
    private def architecture
      ARCHITECTURES.fetch(@platform.name) { raise Error, "an msix installer is for Windows, and #{@platform} is not" }
    end

    # The developer's logo for each of Icon::MSIX's names. Raises
    # Fledge::Error when the app has no icon or a logo is missing.
    private def logos
      icon = @identity.icon || raise(Error, "an msix installer needs fledge.yml's icon. #{Icon::MAKE.fetch('msix')}")
      Icon::MSIX.to_h { |name, size| [name, icon.png(size, "msix")] }
    end

    # The logo named +name+'s path in the package.
    private def logo(name)
      "#{ASSETS}\\#{name}.png"
    end

    # The application's extensions: a file type association for each of
    # the app's file associations that names extensions, which Windows
    # adds to their "Open with" lists. Folders and MIME types alone have
    # no place in a package's manifest.
    private def extensions
      names = [] # : Array[String]
      associations = @identity.file_associations.reject { |association| association.extensions.empty? }
      return [] if associations.empty?

      lines = associations.flat_map do |association|
        name = association_name(association.name, names)
        names << name
        types = association.extensions.map(&:downcase).uniq.map { |extension| "              <uap:FileType>.#{xml(extension)}</uap:FileType>" }
        [
          %(        <uap:Extension Category="windows.fileTypeAssociation">),
          %(          <uap:FileTypeAssociation Name="#{name}">),
          "            <uap:DisplayName>#{xml(association.name)}</uap:DisplayName>",
          "            <uap:SupportedFileTypes>",
          *types,
          "            </uap:SupportedFileTypes>",
          "          </uap:FileTypeAssociation>",
          "        </uap:Extension>",
        ]
      end
      ["      <Extensions>", *lines, "      </Extensions>"]
    end

    # A file type association's name, which the manifest's schema wants in
    # lower case with no spaces: +name+'s letters and digits, with a
    # number after it when one of +taken+ has it already.
    private def association_name(name, taken)
      base = name.downcase.gsub(/[^a-z0-9]/, "")[0, 60].to_s
      base = "files" if base.empty?
      chosen = base
      number = 1
      while taken.include?(chosen)
        number += 1
        chosen = "#{base}#{number}"
      end
      chosen
    end

    # +pairs+ as an element's attributes, each value escaped.
    private def attributes(pairs)
      pairs.map { |key, value| %(#{key}="#{xml(value)}") }.join(" ")
    end

    # +text+ escaped for XML's text and attributes.
    private def xml(text)
      text.to_s.gsub(/[&<>"']/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", '"' => "&quot;", "'" => "&apos;")
    end
  end
end
