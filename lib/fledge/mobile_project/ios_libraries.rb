# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "tmpdir"
require_relative "../binary"
require_relative "../command"
require_relative "../error"
require_relative "../mobile_extensions"

module Fledge
  class MobileProject
    # Puts the libraries an iOS app's Ruby opens by path into the Xcode
    # project, each in a framework of its own, and a link at each path
    # where the gem's Ruby looks for it.
    #
    # A gem's Rakefile may build a library for Ruby's ffi to open by its
    # path in the gem (MobileExtensions::FfiLibrary). iOS takes a
    # third-party dynamic library only inside a framework, in the app's
    # <tt>Frameworks</tt> folder ("Placing content in a bundle",
    # developer.apple.com), and Apple's way to serve code that loads a
    # library by a path where no code may sit is a symbolic link there to
    # where the code is ("Embedding nonstandard code structures in a
    # bundle", developer.apple.com, "Use symlinks for gnarly edge
    # cases"; doc/contributors/design/phone-projects.md, "Libraries for
    # ffi on iOS").
    #
    # This class makes, for each library, a framework for each slice,
    # its binary the library with the install name
    # <tt>@rpath/NAME.framework/NAME</tt>, and its Info.plist, and packs
    # the two with <tt>xcodebuild -create-xcframework</tt> into
    # <tt>Frameworks/NAME.xcframework</tt>, which the project embeds and
    # does not link; and it writes, in the Ruby root, a relative link at
    # each of the library's paths to <tt>Frameworks/NAME.framework/NAME</tt>
    # in the built app's bundle, which dangles in the project and leads to
    # the framework in the app.
    #
    # Use it from MobileProject::IOS, once the extensions are built.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   libraries = Fledge::MobileProject::IOSLibraries.new(built, identifier: "com.example.Hello", version: "1.0.0")
    #   libraries.call(project) # => ["fledgeffi.llhttp-ffi.ext.aarch64-darwin.libllhttp-ext.bundle"]
    #   libraries.link(File.join(project, "fledge"))
    #--
    # SPDX-SnippetEnd
    #++
    class IOSLibraries
      # The folder of the project that holds the frameworks' XCFrameworks.
      FOLDER = "Frameworks"

      # What begins a framework's name: <tt>fledgeffi.GEM.PATH</tt>.
      PREFIX = "fledgeffi"

      # The characters a framework's name may not hold, since it ends its
      # CFBundleIdentifier, which takes only letters, digits, hyphens, and
      # periods (CFBundleIdentifier, developer.apple.com).
      UNSAFE = /[^A-Za-z0-9.-]/

      # The platform each slice's framework is for, as Info.plist's
      # CFBundleSupportedPlatforms names it.
      PLATFORMS = { "ios-arm64" => "iPhoneOS", "ios-arm64-simulator" => "iPhoneSimulator" }.freeze

      # The name of +library+'s framework: PREFIX, its gem's name, and its
      # path in the gem with the slashes as dots, each character outside
      # UNSAFE a hyphen.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOSLibraries.framework_name(library) # => "fledgeffi.scrypt.ext.scrypt.aarch64-darwin.libscrypt-ext.bundle"
      #--
      # SPDX-SnippetEnd
      #++
      def self.framework_name(library)
        "#{PREFIX}.#{library.gem}.#{library.file.tr('/', '.')}".gsub(UNSAFE, "-")
      end

      # What a link at +path+, relative to the Ruby root, which is the
      # app bundle's <tt>fledge/</tt> folder, holds to reach the binary of
      # the framework +name+ in the bundle's <tt>Frameworks/</tt>.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOSLibraries.target("app/ext/libthing.bundle", "fledgeffi.thing.ext.libthing.bundle")
      #   # => "../../../Frameworks/fledgeffi.thing.ext.libthing.bundle.framework/fledgeffi.thing.ext.libthing.bundle"
      #--
      # SPDX-SnippetEnd
      #++
      def self.target(path, name)
        "#{'../' * (path.count('/') + 1)}#{FOLDER}/#{name}.framework/#{name}"
      end

      # The Info.plist of the framework +name+ for the slice whose
      # platform is +platform+, in an app whose bundle identifier is
      # +identifier+ and bundle version +version+: the keys CPython's iOS
      # frameworks carry (<tt>Apple/testbed/Python.xcframework/build/
      # iOS-dylib-Info-template.plist</tt> at v3.14.0), with
      # <tt>FMWK</tt>, a framework's package type, and the app's own
      # minimum iOS.
      #
      # === Example
      #
      #--
      # SPDX-SnippetBegin
      # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
      # SPDX-License-Identifier: MIT-0
      #++
      #   Fledge::MobileProject::IOSLibraries.info("fledgeffi.thing.ext.libthing.so", identifier: "com.example.Hello",
      #     version: "1.0.0", platform: "iPhoneOS")["CFBundleIdentifier"]
      #   # => "com.example.Hello.fledgeffi.thing.ext.libthing.so"
      #--
      # SPDX-SnippetEnd
      #++
      def self.info(name, identifier:, version:, platform:)
        {
          "CFBundleDevelopmentRegion" => "en",
          "CFBundleExecutable" => name,
          "CFBundleIdentifier" => "#{identifier}.#{name}",
          "CFBundleInfoDictionaryVersion" => "6.0",
          "CFBundleName" => name,
          "CFBundlePackageType" => "FMWK",
          "CFBundleShortVersionString" => version,
          "CFBundleSupportedPlatforms" => [platform],
          "CFBundleVersion" => version,
          "MinimumOSVersion" => "15.0",
        }
      end

      # Writes into +project+'s FOLDER the XCFramework of the framework
      # +name+, whose binary for each slice in +slices+ is a copy of the
      # dynamic library at its path there, with the install name
      # <tt>@rpath/NAME.framework/NAME</tt> and the Info.plist #info gives
      # for an app whose bundle identifier is +identifier+ and bundle
      # version +version+, and for each slice in +manifests+ that privacy
      # manifest as its PrivacyInfo.xcprivacy.
      def self.xcframework(project, name, slices, identifier:, version:, manifests: {})
        Dir.mktmpdir("fledge-framework") do |work|
          made = slices.flat_map do |slice, path|
            folder = File.join(work, slice, "#{name}.framework")
            FileUtils.mkdir_p(folder)
            binary = File.join(folder, name)
            FileUtils.cp(path, binary)
            manifest = manifests[slice]
            FileUtils.cp(manifest, File.join(folder, "PrivacyInfo.xcprivacy")) if manifest
            Command.run("xcrun", "install_name_tool", "-id", "@rpath/#{name}.framework/#{name}", binary,
              install: MobileExtensions::INSTALL_XCODE)
            json = File.join(work, "#{slice}.json")
            File.write(json, JSON.generate(info(name, identifier:, version:, platform: PLATFORMS.fetch(slice))))
            Command.run("plutil", "-convert", "xml1", "-o", File.join(folder, "Info.plist"), json, install: MobileExtensions::INSTALL_XCODE)
            ["-framework", folder]
          end
          Command.run("xcodebuild", "-create-xcframework", *made, "-output", File.join(project, FOLDER, "#{name}.xcframework"),
            install: MobileExtensions::INSTALL_XCODE)
        end
      end

      # [built] The MobileExtensions::Built whose libraries the app
      #         carries.
      # [identifier] The app's bundle identifier.
      # [version] The app's bundle version.
      def initialize(built, identifier:, version:)
        @built = built
        @identifier = identifier
        @version = version
      end

      # Each library's framework by its name, with the library for each
      # slice. Raises Fledge::Error for two libraries whose frameworks
      # would have one name, or slices that built different libraries.
      def frameworks
        @frameworks ||= begin
          slices = @built.targets.transform_values { |build| named(build.ffi_libraries) }
          files = slices.values.map { |named| named.transform_values(&:file) }.uniq
          raise Error, "the app's gems built different libraries for ffi for each iOS slice: #{files.map { |named| named.values.sort }.join(' and ')}" if
            files.size > 1

          (files.first || {}).keys.to_h { |name| [name, slices.transform_values { |named| named.fetch(name) }] }
        end
      end

      # Writes each framework's XCFramework into +project+'s FOLDER, and
      # returns their names.
      def call(project)
        frameworks.map do |name, slices|
          IOSLibraries.xcframework(project, name, slices.transform_values(&:path), identifier: @identifier, version: @version)
          name
        end
      end

      # Writes in +ruby_root+ a link at each path of each library to its
      # framework's binary in the app, in place of any file there.
      def link(ruby_root)
        frameworks.each do |name, slices|
          slices.values.first&.links&.each do |path|
            at = File.join(ruby_root, path)
            FileUtils.mkdir_p(File.dirname(at))
            FileUtils.rm_f(at)
            File.symlink(IOSLibraries.target(path, name), at)
          end
        end
      end

      # +libraries+, one slice's, by their frameworks' names, refusing two
      # with one name.
      private def named(libraries)
        named = {} # : Hash[String, MobileExtensions::FfiLibrary]
        libraries.each do |library|
          name = IOSLibraries.framework_name(library)
          if (other = named[name])
            raise Error, "#{other.gem}'s #{other.file} and #{library.gem}'s #{library.file} would both be the framework #{name} " \
              "in the iOS app"
          end

          named[name] = library
        end
        named
      end
    end
  end
end
