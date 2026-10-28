# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "ad_hoc_signature"
require_relative "code_resources"
require_relative "entry"
require_relative "platform"
require_relative "plist"

module Fledge
  # A windowed app on macOS: an <tt>.app</tt> bundle.
  #
  # macOS shows an app's name and icon in the Dock, Cmd-Tab, the menu bar,
  # and Finder only for a bundle, and knows it by the CFBundleIdentifier
  # in the bundle's <tt>Info.plist</tt>, which it checks before it
  # delivers the app's notifications (decision 18; Plan 002, "App
  # identity"). A bare program has none of that, and a double-click on it
  # opens Terminal.
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
  # them, which codesign seals as links. Then it seals every file
  # (Fledge::CodeResources) and signs the launcher ad hoc for the bundle
  # (Fledge::AdHocSignature), so <tt>codesign --verify --strict
  # --deep</tt> passes and Apple Silicon runs it.
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
  #   bundle = Fledge::MacBundle.new(Fledge::App.at("my_app").identity)
  #   bundle.resource("lib/ruby") # => "MyApp.app/Contents/Resources/lib/ruby"
  #   bundle.info_plist           # => "<?xml ..."
  #--
  # SPDX-SnippetEnd
  #++
  class MacBundle
    # What the launcher and Ruby look for beside the launcher, linked from
    # +MacOS+ to +Resources+ when the runtime or the build has them.
    LINKED = %w[app bin fledge.cfg lib libexec].freeze

    # Creates the bundle of the app whose Fledge::Identity is +identity+.
    #
    # [identity] The app's identity: its name, identifier, version,
    #             copyright, and icon.
    def initialize(identity)
      @identity = identity
      @seal = CodeResources.new
      @top = [] # : Array[String]
    end

    # The bundle's folder: <tt>NAME.app</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.folder # => "MyApp.app"
    #--
    # SPDX-SnippetEnd
    #++
    def folder
      "#{@identity.name}.app"
    end

    # Where +path+, a path in a runtime or the app's folder, goes in the
    # bundle: under <tt>Contents/Resources</tt>.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.resource("fledge.cfg") # => "MyApp.app/Contents/Resources/fledge.cfg"
    #--
    # SPDX-SnippetEnd
    #++
    def resource(path)
      first = path.split("/", 2).first.to_s
      @top << first unless @top.include?(first)
      "#{folder}/Contents/Resources/#{path}"
    end

    # Adds +entry+, placed in the built app's folder, to the seal when it
    # is inside the bundle, unless it is the seal or the launcher, which
    # the signature covers itself.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.seal(Fledge::Entry.file("MyApp.app/Contents/Resources/app/main.rb", "puts 1\n"))
    #--
    # SPDX-SnippetEnd
    #++
    def seal(entry)
      contents = "#{folder}/Contents/"
      return unless entry.path.start_with?(contents)

      path = entry.path.delete_prefix(contents)
      @seal.add(entry.with(path:)) unless path.start_with?("_CodeSignature/") || path == "MacOS/#{@identity.name}"
    end

    # The bundle's <tt>Info.plist</tt>: the keys Apple's Information
    # Property List reference requires of a macOS app, its identity, the
    # oldest macOS its runtime runs on (Platform::MACOS_MINIMUM), and that
    # it draws at Retina resolution.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.info_plist.include?("<key>CFBundleIdentifier</key>") # => true
    #--
    # SPDX-SnippetEnd
    #++
    def info_plist
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
      Plist.write(keys)
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

    # What the bundle holds besides the runtime and the app, with paths in
    # the built app's folder: <tt>Info.plist</tt>, the icon, and the links
    # in +MacOS+.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.extras.map(&:path).first # => "MyApp.app/Contents/Info.plist"
    #--
    # SPDX-SnippetEnd
    #++
    def extras
      entries = [Entry.file("#{folder}/Contents/Info.plist", info_plist)]
      icon = @identity.icon
      entries << Entry.file("#{folder}/Contents/Resources/#{icon_file}", icon.icns) if icon
      LINKED.select { |name| @top.include?(name) }.each do |name|
        entries << Entry.symlink("#{folder}/Contents/MacOS/#{name}", "../Resources/#{name}")
      end
      entries
    end

    # The seal and the launcher, signed for the bundle, with paths in the
    # built app's folder. Comes last: the seal covers everything else.
    #
    # [launcher] The runtime's launcher, a Fledge::Entry.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   bundle.finish(launcher).map(&:path)
    #   # => ["MyApp.app/Contents/_CodeSignature/CodeResources", "MyApp.app/Contents/MacOS/MyApp"]
    #--
    # SPDX-SnippetEnd
    #++
    def finish(launcher)
      resources = @seal.bytes
      signer = AdHocSignature.new(identifier: @identity.identifier.to_s, info_plist:, code_resources: resources)
      program = begin
        signer.sign(launcher.content)
      rescue Error => e
        raise Error, "the runtime's launcher #{e.message}"
      end
      [
        Entry.file("#{folder}/Contents/_CodeSignature/CodeResources", resources),
        Entry.file("#{folder}/Contents/MacOS/#{@identity.name}", program, mode: 0o755),
      ]
    end

    private def icon_file
      "#{@identity.name}.icns"
    end
  end
end
