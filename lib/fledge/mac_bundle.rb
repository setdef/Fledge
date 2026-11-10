# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require_relative "command"
require_relative "platform"

module Fledge
  # A windowed app on macOS: an <tt>.app</tt> bundle, signed ad hoc.
  #
  # macOS shows an app's name and icon in the Dock, Cmd-Tab, the menu bar,
  # and Finder only for a bundle, and knows it by the CFBundleIdentifier
  # in the bundle's <tt>Info.plist</tt>, which it checks before it
  # delivers the app's notifications (decision 18; Plan 002, "App
  # identity"). A bare program has none of that, and a double-click on it
  # opens Terminal. Apple Silicon runs only signed code, and
  # <tt>codesign --verify --strict --deep</tt> calls a bundle broken
  # unless its program's signature seals <tt>Info.plist</tt> and every
  # resource.
  #
  # This class lays a built app out as Apple's Bundle Programming Guide
  # lays out a macOS app, and as Tauri's bundler and py2app do:
  #
  #   NAME.app/Contents/Info.plist
  #   NAME.app/Contents/MacOS/NAME             the launcher
  #   NAME.app/Contents/Resources/NAME.icns    the icon
  #   NAME.app/Contents/Resources/...          the runtime and the app
  #   NAME.app/Contents/_CodeSignature/CodeResources
  #
  # Ruby finds its standard library beside the program that holds it
  # (ADR 001; doc/contributors/design/launcher.md, "Finding itself"),
  # and the launcher finds <tt>fledge.cfg</tt> and
  # <tt>app/</tt> there too, but Apple's tools expect only code in
  # <tt>Contents/MacOS</tt>. So the launcher's neighbors live in
  # +Resources+, and LINKED names symbolic links in +MacOS+ that point at
  # them. The launcher runs the app by its real path, in +Resources+, so
  # <tt>$0</tt>, <tt>__FILE__</tt>, and <tt>__dir__</tt> name the folder
  # Ruby's prefix is in (doc/contributors/design/launcher.md, "The app
  # folder in a macOS bundle"). Then it writes <tt>Info.plist</tt> with
  # +plutil+ and signs the bundle ad hoc with +codesign+, which seals every file; both come with
  # macOS (ADR 010).
  #
  # Use it through Fledge::Assembly.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   bundle = Fledge::MacBundle.new(Fledge::App.at("my_app").identity, folder: "dist/MyApp-arm64-darwin")
  #   bundle.resources # => "dist/MyApp-arm64-darwin/MyApp.app/Contents/Resources"
  #   bundle.finish("/tmp/runtime/launcher")
  #--
  # SPDX-SnippetEnd
  #++
  class MacBundle
    # What the launcher and Ruby look for beside the launcher, linked from
    # +MacOS+ to +Resources+ when the runtime or the build has them.
    LINKED = %w[app bin fledge.cfg lib libexec].freeze

    # What to say when this Mac has no codesign or plutil, which every
    # macOS has in /usr/bin.
    INSTALL = "It comes with macOS, in /usr/bin."

    # The bundle an app with +identity+ is on +platform+, built in
    # +folder+: one for a windowed macOS app, and +nil+ for any other.
    def self.for(identity, platform:, folder:, build: nil)
      new(identity, folder:, build:) if platform.os == "darwin" && identity.windowed?
    end

    # Creates the bundle of the app whose Fledge::Identity is +identity+,
    # in the built app's folder +folder+, whose +CFBundleVersion+ is
    # +build+ (Config::Macos), or else the one derived from its version.
    def initialize(identity, folder:, build: nil)
      @identity = identity
      @folder = folder
      @build = build
    end

    # The bundle's path: <tt>FOLDER/NAME.app</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.path # => "dist/MyApp-arm64-darwin/MyApp.app"
    #--
    # SPDX-SnippetEnd
    #++
    def path
      File.join(@folder, "#{@identity.name}.app")
    end

    # Where the runtime and the app go: <tt>Contents/Resources</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.resources # => "dist/MyApp-arm64-darwin/MyApp.app/Contents/Resources"
    #--
    # SPDX-SnippetEnd
    #++
    def resources
      File.join(path, "Contents", "Resources")
    end

    # Where the bundle's programs go: <tt>Contents/MacOS</tt>, which holds
    # its own program and any console program that shares its runtime
    # (ADR 024), as a bundle's helper tools do.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.executables # => "dist/MyApp-arm64-darwin/MyApp.app/Contents/MacOS"
    #--
    # SPDX-SnippetEnd
    #++
    def executables
      File.join(path, "Contents", "MacOS")
    end

    # The keys of the bundle's <tt>Info.plist</tt>: those Apple's
    # Information Property List reference requires of a macOS app, its
    # identity, its build number (+fledge.yml+'s <tt>macos: build</tt>, or
    # its version's), the oldest macOS its runtime runs on
    # (Platform::MACOS_MINIMUM), and that it draws at Retina resolution,
    # as Tauri's bundler writes them.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.info["CFBundleIdentifier"] # => "com.example.MyApp"
    #--
    # SPDX-SnippetEnd
    #++
    def info
      version = MacBundle.bundle_version(@identity.version)
      keys = {
        "CFBundleDevelopmentRegion" => "en",
        "CFBundleDisplayName" => @identity.name,
        "CFBundleExecutable" => @identity.name,
        "CFBundleIdentifier" => @identity.identifier.to_s,
        "CFBundleInfoDictionaryVersion" => "6.0",
        "CFBundleName" => @identity.name,
        "CFBundlePackageType" => "APPL",
        "CFBundleShortVersionString" => version,
        "CFBundleVersion" => @build || version,
        "LSMinimumSystemVersion" => Platform::MACOS_MINIMUM,
        "NSHighResolutionCapable" => true,
      } # : Hash[String, String | bool | Array[Hash[String, String | Array[String]]]]
      keys["CFBundleIconFile"] = icon_file if @identity.icon
      copyright = @identity.copyright
      keys["NSHumanReadableCopyright"] = copyright if copyright
      types = @identity.file_associations.map { |association| MacBundle.document_type(association) }
      keys["CFBundleDocumentTypes"] = types unless types.empty?
      keys
    end

    # The entry of CFBundleDocumentTypes that declares +association+, a
    # Config::FileAssociation (ADR 052): its name and role,
    # ranked +Alternate+, so that macOS offers the app for these files
    # and never makes it their default unless the person does; its
    # extensions and MIME types as electron-builder writes them
    # (+CFBundleTypeExtensions+), and its content types, or
    # <tt>public.folder</tt> for folders, as +LSItemContentTypes+, which
    # macOS reads in place of the others when it is there.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   folder = Fledge::Config::FileAssociation.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [],
    #     content_types: [], folders: true)
    #   Fledge::MacBundle.document_type(folder)
    #   # => {"CFBundleTypeName"=>"Project folder", "CFBundleTypeRole"=>"Viewer", "LSHandlerRank"=>"Alternate",
    #   #     "LSItemContentTypes"=>["public.folder"]}
    #--
    # SPDX-SnippetEnd
    #++
    def self.document_type(association)
      type = {
        "CFBundleTypeName" => association.name,
        "CFBundleTypeRole" => association.role.capitalize,
        "LSHandlerRank" => "Alternate",
      } # : Hash[String, String | Array[String]]
      type["CFBundleTypeExtensions"] = association.extensions unless association.extensions.empty?
      type["CFBundleTypeMIMETypes"] = association.mime_types unless association.mime_types.empty?
      content_types = association.folders ? ["public.folder"] : association.content_types
      type["LSItemContentTypes"] = content_types unless content_types.empty?
      type
    end

    # +version+ as CFBundleShortVersionString and CFBundleVersion take it:
    # at most three numbers between dots, its leading ones, as Apple's
    # Information Property List reference asks.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MacBundle.bundle_version("0.0.1.pre.6") # => "0.0.1"
    #   Fledge::MacBundle.bundle_version("2.1")         # => "2.1"
    #--
    # SPDX-SnippetEnd
    #++
    def self.bundle_version(version)
      version.split(".").take_while { |part| part.match?(/\A\d+\z/) }.first(3).join(".")
    end

    # Puts the launcher at +launcher+ into the bundle as its program,
    # writes <tt>Info.plist</tt>, the icon, and the links in +MacOS+, and
    # signs the bundle: ad hoc, or with +signing+'s identity
    # (Fledge::MacSigning#sign_bundle), which signs each of +helpers+, the
    # console programs already in #executables, first. Comes last: the
    # signature seals everything else. Raises Fledge::Error when plutil or
    # codesign fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.finish("/tmp/runtime/launcher")
    #--
    # SPDX-SnippetEnd
    #++
    def finish(launcher, helpers: [], signing: nil)
      macos = executables
      FileUtils.mkdir_p(macos)
      LINKED.each do |name|
        File.symlink(File.join("..", "Resources", name), File.join(macos, name)) if File.exist?(File.join(resources, name))
      end
      FileUtils.mv(launcher, File.join(macos, @identity.name))
      write_info_plist
      icon = @identity.icon
      FileUtils.cp(icon.file("icns"), File.join(resources, icon_file)) if icon
      return signing.sign_bundle(path, identifier: @identity.identifier.to_s, helpers:) if signing

      Command.run("codesign", "--force", "--sign", "-", "--identifier", @identity.identifier.to_s, path, install: INSTALL)
    end

    # Writes the keys as XML, as +plutil+ converts them from JSON.
    private def write_info_plist
      plist = File.join(path, "Contents", "Info.plist")
      json = "#{plist}.json"
      File.write(json, JSON.generate(info))
      Command.run("plutil", "-convert", "xml1", "-o", plist, json, install: INSTALL)
    ensure
      FileUtils.rm_f(json) if json
    end

    private def icon_file
      "#{@identity.name}.icns"
    end
  end
end
