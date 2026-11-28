# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "yaml"
require_relative "../command"
require_relative "../icon"
require_relative "../binary"
require_relative "../mac_bundle"
require_relative "ios_libraries"
require_relative "ios_ruby_extensions"

module Fledge
  class MobileProject
    # An app's Xcode project for iPhone and iPad, as Fledge::MobileProject
    # describes it.
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

      # Whether +path+ is a Mach-O file, not a link: one of Binary's
      # Mach-O magic numbers, and for a universal file's, which a Java
      # class file shares, a count of architectures below 45: a class
      # file has its minor and major versions there, and no major version
      # is below 45 (The Java Virtual Machine Specification, section 4.1).
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOS.mach_o?("ext/aarch64-darwin/llhttp/api.o") # => true
      #--
      # SPDX-SnippetEnd
      #++
      def self.mach_o?(path)
        return false unless File.file?(path) && !File.symlink?(path)

        head = File.binread(path, 8).to_s
        return false unless Binary.format_of(head) == :macho

        !head.start_with?("\xCA\xFE\xBA\xBE".b) || head.byteslice(4, 4).to_s.unpack1("N").to_i.between?(1, 44)
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
"LDFLAGS" => ["$(inherited)", *extension_flags, *main_thread_flags].join(" "),
"RUBY_EMBED" => ruby_extensions.dynamic?,
}.transform_values { |value| JSON.generate(value) }
        frameworks = @ruby_frameworks || [] # : Array[String]
        frameworks += libraries.frameworks.keys if @built
        strings.merge("EXTENSIONS" => IOS.dependencies(extensions: !@built.nil?, frameworks:))
      end

      # The block of <tt>project.yml</tt>'s dependencies that the mark
      # +EXTENSIONS+ stands for: FledgeExtensions.xcframework, linked, when
      # the app's gems have +extensions+, and each of +frameworks+, the
      # runtime's own extensions and the libraries for Ruby's ffi, embedded
      # and not linked, since Ruby or its ffi opens each by its path, as on
      # a desktop, where no program links it.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOS.dependencies(extensions: false, frameworks: []) # => ""
      #--
      # SPDX-SnippetEnd
      #++
      def self.dependencies(extensions:, frameworks:)
        blocks = frameworks.map { |name| "- framework: #{IOSLibraries::FOLDER}/#{name}.xcframework\n        embed: true\n        link: false" }
        blocks.unshift("- framework: #{EXTENSIONS}\n        embed: false") if extensions
        blocks.join("\n      ")
      end

      # The linker's flag that gives the main thread, where every app's
      # Ruby runs,
      # a 64 MB stack, as test/fixtures/sdl_phone's host asks for it.
      private def main_thread_flags
        ["-Wl,-stack_size,0x4000000"]
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

      # Links the extensions into the app: one static library for each slice,
      # made by Apple's libtool from the archives mkmf made, packed by
      # <tt>xcodebuild -create-xcframework</tt> as the runtime's is, which
      # the project links; and the registration unit
      # in <tt>Host/</tt>, which Xcode compiles with the host app, so its
      # constructor registers each extension when the app starts. Each
      # library for Ruby's ffi that a gem's Rakefile built is a framework
      # of its own (IOSLibraries).
      private def place_extensions(project)
        built = @built or return
        libraries.call(project)
        Dir.mktmpdir("fledge-extensions") do |work|
          slices = built.targets.flat_map do |name, build|
            library = File.join(work, name, "libFledgeExtensions.a")
            FileUtils.mkdir_p(File.dirname(library))
            Command.run("xcrun", "libtool", "-static", "-no_warning_for_no_symbols", "-o", library, *build.archives, install: Fledge::MobileExtensions::INSTALL_XCODE)
            ["-library", library]
          end
          Command.run("xcodebuild", "-create-xcframework", *slices, "-output", File.join(project, EXTENSIONS), install: Fledge::MobileExtensions::INSTALL_XCODE)
        end
        File.write(File.join(project, "Host", "fledge_extensions.c"), MobileExtensions.registration_source(built.registrations, header:))
      end

      # The name the app's build finds the embedding API's header by: in
      # FledgeRuby.framework, as a framework's headers are found, or in
      # the Headers folder of a static FledgeRuby.xcframework.
      private def header
        ruby_extensions.dynamic? ? "FledgeRuby/fledge_ruby.h" : "fledge_ruby.h"
      end

      # The frameworks of the libraries for Ruby's ffi that the app's
      # gems built.
      private def libraries
        built = @built or raise Error, "the app has no extensions"
        @libraries ||= IOSLibraries.new(built, identifier:, version: MacBundle.bundle_version(@app.identity.version))
      end

      # Puts a link at each path where a gem looks for a library for
      # Ruby's ffi, to its framework in the app (IOSLibraries#link), and
      # leaves out of +root+ every other Mach-O file the app's gems hold,
      # saying which: iOS lets an app carry compiled code only as its
      # executable and in its frameworks ("Placing content in a bundle",
      # developer.apple.com), and a gem's package may hold what its
      # author built on a Mac, as llhttp-ffi 0.5.1's holds the library
      # and the object files its Rakefile made there.
      private def place_links(root)
        libraries.link(root)
        found = Dir.glob("**/*", File::FNM_DOTMATCH, base: root).sort.select { |path| IOS.mach_o?(File.join(root, path)) }
        return if found.empty?

        found.each { |path| File.delete(File.join(root, path)) }
        @log&.puts "Left out of the iOS app, which carries compiled code only in its executable and its frameworks: #{found.join(', ')}"
      end

      # Moves the runtime into +project+, with a framework of each of its
      # own extensions and a link at each one's path (IOSRubyExtensions).
      private def place_runtime(tree, project)
        FileUtils.mv(File.join(tree, FRAMEWORK), project)
        extensions = @ruby_extensions = IOSRubyExtensions.new(File.join(project, FRAMEWORK))
        @ruby_frameworks = extensions.call(project, identifier:, version: MacBundle.bundle_version(@app.identity.version))
        extensions.link
      end

      private def ruby_extensions
        @ruby_extensions or raise Error, "the iOS runtime is not in the project yet"
      end

      # Raises Fledge::Error when +project+'s <tt>project.yml</tt> links
      # a dynamic FledgeRuby.xcframework without embedding it, as a host's
      # copy of a template from before the runtime's Ruby was a framework
      # does (<tt>embed: false</tt>): the app would stop as it starts,
      # since iOS's loader would find no FledgeRuby in it.
      private def check_ruby_embedded(project)
        spec = YAML.safe_load_file(File.join(project, "project.yml"))
        targets = spec.is_a?(Hash) ? spec["targets"] : nil
        listed = targets.is_a?(Hash) ? targets.values : [] # : Array[Object]
        dependencies = listed.flat_map do |target|
          target.is_a?(Hash) ? Array(target["dependencies"]) : [] # : Array[Object]
        end
        ruby = dependencies.select { |dependency| dependency.is_a?(Hash) && dependency["framework"] == FRAMEWORK }
        return if ruby.all? { |dependency| dependency.is_a?(Hash) && dependency["embed"] == true }

        raise Error, "project.yml links #{FRAMEWORK} without embedding it, and the runtime's Ruby is a framework the app must embed: " \
          "give its dependency embed: @@RUBY_EMBED@@, as Fledge's template does"
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
        check_ruby_embedded(project) if ruby_extensions.dynamic?
        Command.run("xcodegen", "generate", "--quiet", "--spec", File.join(project, "project.yml"), "--project", project, install: INSTALL)
      end
    end
  end
end
