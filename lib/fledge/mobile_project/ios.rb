# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require_relative "../command"
require_relative "../icon"
require_relative "../mac_bundle"

module Fledge
  class MobileProject
    # An app's Xcode project for iPhone and iPad, as Fledge::MobileProject
    # describes it (ADR 012).
    #
    # The project is XcodeGen's, as Tauri's iOS projects are: Fledge writes
    # XcodeGen's <tt>project.yml</tt> from its template, with the app's
    # name, identifier, and version, and XcodeGen writes
    # <tt>NAME.xcodeproj</tt> from it, so Fledge writes no Xcode project
    # file of its own. Beside it go the runtime's
    # <tt>FledgeRuby.xcframework</tt>, whose slices each hold the Ruby
    # they run, which the project's build phase copies into the app's
    # bundle with ROOT for the SDK it builds for; the host app,
    # <tt>Host/main.m</tt>, with its <tt>Info.plist</tt> and its privacy
    # manifest; and, when <tt>fledge.yml</tt> names an icon, an asset
    # catalog whose app icon is <tt>ICON-1024.png</tt>, from which Xcode
    # makes the rest.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::MobileProject::IOS.new(app:, runtime:, out:).call # => "/path/to/dist/Hello-ios"
    #--
    # SPDX-SnippetEnd
    #++
    class IOS < MobileProject
      # The runtime's XCFramework.
      FRAMEWORK = "FledgeRuby.xcframework"

      # The XCFramework's slice for devices, whose Ruby the app's gems
      # are checked against; the Simulator's has the same files.
      SLICE = "ios-arm64"

      # The XCFramework of the app's gems' extensions, for an app that has any.
      EXTENSIONS = "FledgeExtensions.xcframework"

      # The asset catalog the template holds for an app with an icon.
      ASSETS = "Host/Assets.xcassets"

      # How to get XcodeGen, for the message when it is missing.
      INSTALL = "Install XcodeGen, which writes the Xcode project: brew install xcodegen, or its release from " \
        "https://github.com/yonaskolb/XcodeGen/releases."

      # Where the runtime's Ruby for devices is in its archive, for
      # Fledge::RuntimeContents.read.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOS.ruby_under # => "FledgeRuby.xcframework/ios-arm64/"
      #--
      # SPDX-SnippetEnd
      #++
      def self.ruby_under
        "#{FRAMEWORK}/#{SLICE}/"
      end

      private def system
        "ios"
      end

      private def template_files
        ["project.yml"]
      end

      # The values for <tt>project.yml</tt>'s marks, each a JSON string,
      # which YAML reads as a quoted one, but for the dependency of an
      # app whose gems have extensions, a block of the file's own.
      private def tokens
        icon = @app.identity.icon ? "AppIcon" : ""
        version = MacBundle.bundle_version(@app.identity.version)
        strings = {
"NAME" => @app.name,
"IDENTIFIER" => identifier,
"VERSION" => version,
"APP_ICON" => icon,
"LDFLAGS" => ["$(inherited)", *extension_flags].join(" "),
}.transform_values { |value| JSON.generate(value) }
        strings.merge("EXTENSIONS" => @built ? "- framework: #{EXTENSIONS}\n        embed: false" : "")
      end

      # The linker flags the extensions' extconf.rb files asked for, and
      # the C++ runtime for an extension that has C++, for both slices.
      private def extension_flags
        built = @built or return []
        builds = built.targets.values
        [
          *builds.flat_map(&:flags),
          *(builds.any?(&:cxx) ? ["-lc++"] : [] # : Array[String]
           ),
].uniq
      end

      # Links the extensions into the app (ADR 022): one static library
      # for each slice, made by Apple's libtool from the archives mkmf made,
      # packed by <tt>xcodebuild -create-xcframework</tt> as the
      # runtime's is, which the project links; and the registration unit
      # in <tt>Host/</tt>, which Xcode compiles with the host app, so its
      # constructor registers each extension when the app starts.
      private def place_extensions(project)
        built = @built or return
        Dir.mktmpdir("fledge-extensions") do |work|
          libraries = built.targets.flat_map do |name, build|
            library = File.join(work, name, "libFledgeExtensions.a")
            FileUtils.mkdir_p(File.dirname(library))
            Command.run("xcrun", "libtool", "-static", "-no_warning_for_no_symbols", "-o", library, *build.archives, install: Fledge::MobileExtensions::INSTALL_XCODE)
            ["-library", library]
          end
          Command.run("xcodebuild", "-create-xcframework", *libraries, "-output", File.join(project, EXTENSIONS), install: Fledge::MobileExtensions::INSTALL_XCODE)
        end
        File.write(File.join(project, "Host", "fledge_extensions.c"), MobileExtensions.registration_source(built.registrations))
      end

      private def place_runtime(tree, project)
        FileUtils.mv(File.join(tree, FRAMEWORK), project)
      end

      private def ruby_root(project)
        File.join(project, FRAMEWORK, SLICE)
      end

      private def place_icons(project)
        icon = @app.identity.icon
        return FileUtils.rm_rf(File.join(project, ASSETS)) unless icon

        FileUtils.cp(icon.png(Icon::IOS, "ios"), File.join(project, ASSETS, "AppIcon.appiconset", "AppIcon.png"))
      end

      # Has XcodeGen write the Xcode project from <tt>project.yml</tt>.
      private def finish(project)
        Command.run("xcodegen", "generate", "--quiet", "--spec", File.join(project, "project.yml"), "--project", project, install: INSTALL)
      end
    end
  end
end
