# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # Ruby finds its standard library beside the program that holds it (ADR
  # 001, section 1), and the launcher finds <tt>fledge.cfg</tt> and
  # <tt>app/</tt> there too, but Apple's tools expect only code in
  # <tt>Contents/MacOS</tt>. So the launcher's neighbors live in
  # +Resources+, and LINKED names symbolic links in +MacOS+ that point at
  # them. Then it writes <tt>Info.plist</tt> with +plutil+ and signs the
  # bundle ad hoc with +codesign+, which seals every file, as Xcode's
  # command line tools do on every Mac that builds Mac apps (ADR 010).
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

    # What to do when this Mac has no codesign or plutil.
    INSTALL = "Install Xcode's command line tools: xcode-select --install."

    # Creates the bundle of the app whose Fledge::Identity is +identity+,
    # in the built app's folder +folder+.
    def initialize(identity, folder:)
      @identity = identity
      @folder = folder
    end

    # The bundle's path: <tt>FOLDER/NAME.app</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.resources # => "dist/MyApp-arm64-darwin/MyApp.app/Contents/Resources"
    #--
    # SPDX-SnippetEnd
    #++
    def resources
      File.join(path, "Contents", "Resources")
    end

    # The keys of the bundle's <tt>Info.plist</tt>: those Apple's
    # Information Property List reference requires of a macOS app, its
    # identity, the oldest macOS its runtime runs on
    # (Platform::MACOS_MINIMUM), and that it draws at Retina resolution,
    # as Tauri's bundler writes them.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
        "CFBundleVersion" => version,
        "LSMinimumSystemVersion" => Platform::MACOS_MINIMUM,
        "NSHighResolutionCapable" => true,
      } # : Hash[String, String | bool]
      keys["CFBundleIconFile"] = icon_file if @identity.icon
      copyright = @identity.copyright
      keys["NSHumanReadableCopyright"] = copyright if copyright
      keys
    end

    # +version+ as CFBundleShortVersionString and CFBundleVersion take it:
    # at most three numbers between dots, its leading ones, as Apple's
    # Information Property List reference asks.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
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
    # signs the bundle ad hoc. Comes last: the signature seals everything
    # else. Raises Fledge::Error when plutil or codesign fails.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.finish("/tmp/runtime/launcher")
    #--
    # SPDX-SnippetEnd
    #++
    def finish(launcher)
      macos = File.join(path, "Contents", "MacOS")
      FileUtils.mkdir_p(macos)
      LINKED.each do |name|
        File.symlink(File.join("..", "Resources", name), File.join(macos, name)) if File.exist?(File.join(resources, name))
      end
      FileUtils.mv(launcher, File.join(macos, @identity.name))
      write_info_plist
      icon = @identity.icon
      FileUtils.cp(icon.file("icns"), File.join(resources, icon_file)) if icon
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
