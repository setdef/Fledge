# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"

class MobileParity
  # The archive App Store Connect would take, as far as Apple's own tools
  # show without an account: an app's Xcode
  # project archived for devices with xcodebuild, unsigned, and what
  # App Store Connect requires of the archive and the app in it checked
  # in the files, with plutil, vtool, otool, lipo, and assetutil. What
  # needs the account, signing, exporting, and uploading, is not run.
  class IOSArchive
    # What an app's Info.plist must hold, as Xcode writes it into the
    # built app: the keys Apple's "Information Property List" pages mark
    # as required by the App Store (CFBundleVersion,
    # UIRequiredDeviceCapabilities), and the ones that make the app the
    # iPhone and iPad app on devices the project says it is.
    REQUIRED_KEYS = %w[
      CFBundleIdentifier
      CFBundleExecutable
      CFBundleName
      CFBundlePackageType
      CFBundleShortVersionString
      CFBundleVersion
      MinimumOSVersion
      UIDeviceFamily
      UIRequiredDeviceCapabilities
      DTXcode
      DTSDKName
      DTPlatformName
    ].freeze

    # One to three integers, as Apple's CFBundleVersion page says its
    # value is composed.
    VERSION = /\A\d+(\.\d+){0,2}\z/

    # The first four bytes of a Mach-O file, as dyld's loader.h names
    # them, in the order a file holds them: thin 32 and 64 bit files of
    # either byte order, and a fat file (whose magic is also Java's, so a
    # file of four more bytes is needed to count).
    MACH_O = [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe].freeze

    # Ruby's framework, which an app embeds when its runtime's Ruby is
    # dynamic, and the install name its extensions' frameworks and the
    # executable load it by.
    RUBY = "FledgeRuby"
    RUBY_INSTALL_NAME = "@rpath/#{RUBY}.framework/#{RUBY}".freeze

    # A symbol only OpenSSL defines, by which a framework's binary is
    # known to hold it: Apple lists OpenSSL among the SDKs that need a
    # privacy manifest of their own when an app carries them ("Upcoming
    # third-party SDK requirements", developer.apple.com), as CPython's
    # iOS build carries OpenSSL's in its _ssl and _hashlib modules'
    # frameworks (Doc/using/ios.rst at v3.14.0, lines 348 to 361).
    OPENSSL = "_OPENSSL_init_crypto"

    # The problems with an app's +info+ (its Info.plist as a Hash): one
    # message for each, naming the key. +identifier+ and +executable+ are
    # what the project names; +icon+ is whether the app has an icon.
    def self.info_problems(info, identifier:, executable:, icon:)
      missing = REQUIRED_KEYS.reject { |key| info.key?(key) }
      problems = missing.map { |key| "Info.plist has no #{key}, which App Store Connect requires" }
      problems << "Info.plist has neither UILaunchScreen nor UILaunchStoryboardName, so the app has no launch screen" unless
        info.key?("UILaunchScreen") || info.key?("UILaunchStoryboardName")
      problems.concat(mismatches(info, identifier, executable))
      problems.concat(device_problems(info))
      problems.concat(versions_problems(info))
      problems.concat(icon_problems(info, icon))
      problems
    end

    private_class_method def self.mismatches(info, identifier, executable)
      {
        "CFBundleIdentifier" => identifier,
        "CFBundleExecutable" => executable,
        "CFBundlePackageType" => "APPL",
        "MinimumOSVersion" => "15.0",
        "DTPlatformName" => "iphoneos",
      }.filter_map do |key, expected|
        "Info.plist's #{key} is #{info[key].inspect}, not #{expected.inspect}" if info.key?(key) && info[key] != expected
      end
    end

    private_class_method def self.device_problems(info)
      problems = []
      problems << "Info.plist's UIDeviceFamily is #{info['UIDeviceFamily'].inspect}, not [1, 2] (iPhone and iPad)" if
        info.key?("UIDeviceFamily") && info["UIDeviceFamily"] != [1, 2]
      problems << "Info.plist's UIRequiredDeviceCapabilities lacks arm64, which Apple says every 64-bit app includes" if
        info.key?("UIRequiredDeviceCapabilities") && !Array(info["UIRequiredDeviceCapabilities"]).include?("arm64")
      problems << "Info.plist's CFBundleSupportedPlatforms is #{info['CFBundleSupportedPlatforms'].inspect}, not [\"iPhoneOS\"]" unless
        info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
      problems
    end

    private_class_method def self.versions_problems(info)
      %w[CFBundleShortVersionString CFBundleVersion].filter_map do |key|
        "Info.plist's #{key} is #{info[key].inspect}, not one to three integers" if info.key?(key) && !info[key].to_s.match?(VERSION)
      end
    end

    private_class_method def self.icon_problems(info, icon)
      return [] unless icon

      name = info.dig("CFBundleIcons", "CFBundlePrimaryIcon", "CFBundleIconName")
      (name == "AppIcon") ? [] : ["Info.plist's CFBundleIconName is #{name.inspect}, not \"AppIcon\", though the app has an icon"]
    end

    # What +info+ says of export compliance: ITSAppUsesNonExemptEncryption
    # is the developer's declaration to the U.S. export rules, so Fledge
    # writes none and the check reports it.
    def self.encryption(info)
      info.key?("ITSAppUsesNonExemptEncryption") ? "declared #{info['ITSAppUsesNonExemptEncryption']}" : "not declared"
    end

    # What to say of +info+'s version when it is 0.0.0, which is what an
    # app with no <tt>version</tt> in fledge.yml has: Apple's reference
    # for CFBundleVersion allows it ("0 specifies 0.0.0"), and no Apple
    # page says App Store Connect refuses it, so it is noted, not failed.
    # Nil for any other version.
    def self.version_note(info)
      return unless info["CFBundleShortVersionString"] == "0.0.0"

      "its version is 0.0.0, since fledge.yml has no version; give it one before it goes in a store"
    end

    # Whether the PNG at +path+ has an alpha channel: a color type of
    # gray with alpha (4) or RGBA (6), or a tRNS chunk, as the PNG
    # specification (W3C, section 11.3.2) gives transparency to the
    # other color types. App Store Connect refuses a large app icon that
    # has one, even if every pixel is opaque.
    def self.alpha?(path)
      data = File.binread(path)
      raise "#{path} is not a PNG" unless data.start_with?("\x89PNG\r\n\x1a\n".b)

      return true if [4, 6].include?(data.getbyte(25))

      offset = 8
      while offset < data.bytesize
        length, type = data.unpack("Na4", offset:)
        return true if type == "tRNS"
        break if type == "IDAT"

        offset += 12 + length
      end
      false
    end

    # What a framework's Info.plist, +info+, must hold for its binary
    # +name+: the keys of Fledge's own (MobileProject::IOSLibraries.info),
    # with FMWK, a framework's package type (CFBundlePackageType,
    # developer.apple.com), the device's platform and iOS 15, as the
    # app's, and versions of one to three integers.
    def self.framework_info_problems(info, name)
      expected = {
"CFBundleExecutable" => name,
"CFBundlePackageType" => "FMWK",
"MinimumOSVersion" => "15.0",
"CFBundleSupportedPlatforms" => ["iPhoneOS"],
"CFBundleInfoDictionaryVersion" => "6.0",
}
      problems = expected.filter_map { |key, value| "Info.plist's #{key} is #{info[key].inspect}, not #{value.inspect}" unless info[key] == value }
      problems << "Info.plist has no CFBundleIdentifier" unless info["CFBundleIdentifier"].is_a?(String) && !info["CFBundleIdentifier"].empty?
      problems + %w[CFBundleShortVersionString CFBundleVersion].filter_map do |key|
        "Info.plist's #{key} is #{info[key].inspect}, not one to three integers" unless info[key].to_s.match?(VERSION)
      end
    end

    # The links under +root+, relative to it, that lead to no file inside
    # it.
    def self.links_out(root)
      inside = File.join(File.realpath(root), "")
      Dir.glob("**/*", File::FNM_DOTMATCH, base: root).select do |relative|
        path = File.join(root, relative)
        next false unless File.symlink?(path)

        !File.exist?(path) || !File.realpath(path).start_with?(inside)
      end.sort
    end

    # The files under +root+, relative to it, that are Mach-O files, but
    # for the file +except+ and links: an app of Fledge's carries none but
    # its executable and its frameworks' binaries (its extensions link
    # into the executable), and App Store Connect would want any
    # other signed and in a framework.
    def self.mach_o_files(root, except:)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: root).select do |relative|
        path = File.join(root, relative)
        File.file?(path) && !File.symlink?(path) && relative != except && File.size(path) > 4 && mach_o?(path)
      end.sort
    end

    private_class_method def self.mach_o?(path)
      MACH_O.include?(File.binread(path, 4).unpack1("N"))
    end

    # +path+'s property list as a Hash, which plutil, Apple's tool,
    # converts to JSON, or only its value at +keypath+, for a list that
    # holds a date, which JSON cannot; it raises when the list is not
    # valid.
    def self.read_plist(path, keypath = nil)
      command = keypath ? ["-extract", keypath, "json"] : ["-convert", "json"]
      out, err, status = Open3.capture3("plutil", *command, "-o", "-", path)
      raise "plutil rejects #{path}: #{err}" unless status.success?

      JSON.parse(out)
    end

    # The +app+ (a MobileParity::App) whose Xcode +project+ is archived,
    # in +work+; +icon+ is whether its fledge.yml names an icon.
    def initialize(app:, project:, work:, icon:, out: $stdout)
      @app = app
      @project = project
      @work = work
      @icon = icon
      @out = out
    end

    # Archives the project for devices, unsigned, and raises with every
    # problem found in the archive, or prints what was checked.
    def call
      archive = make_archive
      bundle = File.join(archive, "Products", "Applications", "#{@app.name}.app")
      executable = File.join(bundle, @app.name)
      problems = [*archive_problems(archive), *bundle_problems(bundle, executable)]
      raise "#{@app.name}'s archive would not pass App Store Connect:\n- #{problems.join("\n- ")}" unless problems.empty?

      info = IOSArchive.read_plist(File.join(bundle, "Info.plist"))
      @out.puts "Archived #{@app.name} unsigned: iOS #{info['MinimumOSVersion']}, arm64, version #{info['CFBundleShortVersionString']} " \
        "(#{info['CFBundleVersion']}), #{@icon ? 'a 1024 pixel icon without alpha' : 'no icon (App Store Connect needs one)'}, " \
        "export compliance #{IOSArchive.encryption(info)}"
      note = IOSArchive.version_note(info)
      @out.puts "#{@app.name}: #{note}" if note
      bundle
    end

    # xcodebuild's archive action, which writes an .xcarchive as Xcode's
    # Product > Archive does, for the device SDK and the Release
    # configuration, with signing off, and which must warn of nothing.
    private def make_archive
      archive = File.join(@work, "#{@app.identifier}.xcarchive")
      log = File.join(@work, "xcarchive-#{@app.identifier}.log")
      FileUtils.rm_rf(archive)
      made = system("xcodebuild", "-project", File.join(@project, "#{@app.name}.xcodeproj"), "-scheme", @app.name,
        "-configuration", "Release", "-sdk", "iphoneos", "-archivePath", archive,
        "-derivedDataPath", File.join(@work, "derived-archive-#{@app.identifier}"), "archive", "CODE_SIGNING_ALLOWED=NO",
        out: log, err: [:child, :out])
      raise "xcodebuild archive failed for #{@app.name}:\n#{File.readlines(log).last(60).join}" unless made

      warnings = File.readlines(log).grep(/\bwarning:/).uniq
      raise "xcodebuild archive warned for #{@app.name}:\n#{warnings.join}" unless warnings.empty?

      archive
    end

    # What an .xcarchive holds: its Info.plist naming the app, and the
    # app's dSYM, which App Store Connect takes for symbolication.
    private def archive_problems(archive)
      properties = IOSArchive.read_plist(File.join(archive, "Info.plist"), "ApplicationProperties")
      problems = []
      problems << "the archive's Info.plist names #{properties['ApplicationPath'].inspect}, not Applications/#{@app.name}.app" unless
        properties["ApplicationPath"] == "Applications/#{@app.name}.app"
      problems << "the archive's Info.plist names the architectures #{properties['Architectures'].inspect}, not [\"arm64\"]" unless
        properties["Architectures"] == ["arm64"]
      problems << "the archive has no dSYM for #{@app.name}" unless
        File.file?(File.join(archive, "dSYMs", "#{@app.name}.app.dSYM", "Contents", "Resources", "DWARF", @app.name))
      problems
    end

    private def bundle_problems(bundle, executable)
      info = IOSArchive.read_plist(File.join(bundle, "Info.plist"))
      [
        *IOSArchive.info_problems(info, identifier: @app.identifier, executable: @app.name, icon: @icon),
        *executable_problems(executable),
        *bundle_content_problems(bundle),
        *privacy_problems(bundle),
        *(@icon ? icon_asset_problems(bundle) : []),
      ]
    end

    # The executable is for iOS devices only: arm64 alone, a device's
    # platform and iOS 15 as its minimum in vtool's report, no bitcode (which Xcode 14
    # and later neither makes nor App Store Connect takes), and only
    # Apple's own libraries and frameworks, which are on every device,
    # and Ruby's framework, where the runtime's Ruby is dynamic, in
    # otool's list, so nothing is missing or loaded from a folder of the
    # app but Ruby's framework, which the app embeds.
    # A framework's binary is checked the same way, +own+ its install
    # name, which otool lists first.
    private def executable_problems(executable, own: nil)
      problems = []
      archs = capture("xcrun", "lipo", "-archs", executable).split
      problems << "the executable's architectures are #{archs}, not [\"arm64\"]" unless archs == ["arm64"]
      build = capture("xcrun", "vtool", "-show-build", executable)
      problems << "the executable is not built for iOS devices:\n#{build}" unless build.match?(/^\s*platform IOS$/)
      problems << "the executable's minos is not 15.0:\n#{build}" unless build.match?(/^\s*minos 15\.0$/)
      problems << "the executable holds bitcode (an __LLVM segment)" if capture("xcrun", "otool", "-l", executable).include?("segname __LLVM")
      libraries = capture("xcrun", "otool", "-L", executable).lines.drop(1).map { |line| line.split.first }
      others = libraries.reject do |library|
        library.start_with?("/usr/lib/", "/System/Library/") || library == own || (ruby_dynamic? && library == RUBY_INSTALL_NAME)
      end
      problems << "the executable loads #{others.join(', ')}, which no device has" unless others.empty?
      problems
    end

    # Nothing in the bundle but the executable and the binaries of the
    # frameworks the project embeds is Mach-O, the bundle has no folder
    # of extensions or watch apps, and nothing is signed. The frameworks
    # are Ruby's own, where the runtime's Ruby is dynamic, its
    # extensions', and the libraries for Ruby's ffi a gem's build made,
    # each of which iOS takes only in a framework of its own in the app's
    # Frameworks folder ("Placing content in a bundle",
    # developer.apple.com): the Frameworks folder holds exactly Ruby's
    # and those the project's <tt>Frameworks/</tt> folder has an
    # XCFramework of, each as
    # FRAMEWORK_KEYS and #framework_problems check it. Every link in the
    # bundle leads to a file inside it, as Apple's way of serving code
    # that loads a library by its path makes one ("Embedding nonstandard
    # code structures in a bundle", developer.apple.com, "Use symlinks
    # for gnarly edge cases").
    private def bundle_content_problems(bundle)
      problems = %w[PlugIns Watch SC_Info embedded.mobileprovision _CodeSignature].filter_map do |name|
        "the app has #{name}, which Fledge's project does not embed or sign" if File.exist?(File.join(bundle, name))
      end
      names = [
        *Dir.glob("*.xcframework", base: File.join(@project, "Frameworks")).map { |name| File.basename(name, ".xcframework") },
        *(ruby_dynamic? ? [RUBY] : []),
].sort
      embedded = Dir.exist?(File.join(bundle, "Frameworks")) ? Dir.children(File.join(bundle, "Frameworks")).sort : []
      problems << "the app's Frameworks holds #{embedded}, not the project's #{names.map { |name| "#{name}.framework" }}" unless
        embedded == names.map { |name| "#{name}.framework" }
      binaries = names.map { |name| "Frameworks/#{name}.framework/#{name}" }
      found = IOSArchive.mach_o_files(bundle, except: @app.name) - binaries
      problems << "the app holds Mach-O files besides its executable and its frameworks': #{found.join(', ')}" unless found.empty?
      problems.concat(binaries.flat_map { |binary| framework_problems(bundle, binary) }) if embedded == names.map { |name| "#{name}.framework" }
      problems.concat(IOSArchive.links_out(bundle).map { |link| "the app's link #{link} does not lead to a file in the app" })
      problems
    end

    # What the framework whose binary is at +binary+ in +bundle+ must be:
    # its Info.plist as IOSArchive.framework_info_problems checks it, and
    # its binary a dynamic library (a bundle, which ffi-compiler links on
    # Apple systems, goes in no framework: Apple's table puts a
    # framework's dynamic library in Frameworks and a plug-in elsewhere,
    # and PEP 730 says one "must be compiled as dynamic libraries, not
    # shared objects or binary bundles") for iOS devices, as the
    # executable is, unsigned, which loads nothing but Apple's own
    # libraries and Ruby's; and, if it holds OpenSSL (OPENSSL), with
    # a privacy manifest (#openssl_problems).
    private def framework_problems(bundle, binary)
      folder = File.join(bundle, File.dirname(binary))
      name = File.basename(binary)
      path = File.join(bundle, binary)
      info = File.file?(File.join(folder, "Info.plist")) ? IOSArchive.read_plist(File.join(folder, "Info.plist")) : {}
      problems = IOSArchive.framework_info_problems(info, name).map { |problem| "#{name}.framework: #{problem}" }
      kind = capture("xcrun", "otool", "-hv", path).lines.last.split[4]
      problems << "#{binary} is a #{kind}, not a dynamic library (DYLIB)" unless kind == "DYLIB"
      problems << "#{name}.framework is signed, which Fledge's project leaves to Xcode" if File.exist?(File.join(folder, "_CodeSignature"))
      problems.concat(executable_problems(path, own: "@rpath/#{name}.framework/#{name}").map { |problem| problem.sub("the executable", binary) })
      problems.concat(openssl_problems(folder, path))
    end

    # A framework whose binary, at +path+ in +folder+, exports OpenSSL's
    # symbols has a privacy manifest that plutil takes.
    private def openssl_problems(folder, path)
      return [] unless capture("xcrun", "nm", "-gjU", path).split.include?(OPENSSL)

      manifest = File.join(folder, "PrivacyInfo.xcprivacy")
      name = File.basename(folder)
      return ["#{name} holds OpenSSL but has no PrivacyInfo.xcprivacy"] unless File.file?(manifest)

      _, err, status = Open3.capture3("plutil", "-lint", manifest)
      status.success? ? [] : ["#{name}'s PrivacyInfo.xcprivacy is not a valid property list: #{err}"]
    end

    # Whether the runtime in the project holds Ruby as a dynamic
    # framework, which the app embeds.
    private def ruby_dynamic?
      Dir.exist?(File.join(@project, "#{RUBY}.xcframework", "ios-arm64", "#{RUBY}.framework"))
    end

    # The privacy manifest is in the app, a valid property list (plutil
    # -lint's test), and holds the four keys Apple's "Privacy manifest
    # files" page lists.
    private def privacy_problems(bundle)
      manifest = File.join(bundle, "PrivacyInfo.xcprivacy")
      return ["the app has no PrivacyInfo.xcprivacy"] unless File.file?(manifest)

      _, err, status = Open3.capture3("plutil", "-lint", manifest)
      return ["PrivacyInfo.xcprivacy is not a valid property list: #{err}"] unless status.success?

      keys = IOSArchive.read_plist(manifest).keys
      (%w[NSPrivacyTracking NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes NSPrivacyAccessedAPITypes] - keys).map do |key|
        "PrivacyInfo.xcprivacy has no #{key}"
      end
    end

    # The app's icon: its asset catalog, compiled into Assets.car,
    # holds the app icon's 1024 pixel image for the store, as assetutil
    # lists it, and the PNG it was made from has no alpha channel.
    private def icon_asset_problems(bundle)
      return ["the app has no Assets.car, so none of the icon's images"] unless File.file?(File.join(bundle, "Assets.car"))

      renditions = JSON.parse(capture("xcrun", "assetutil", "--info", File.join(bundle, "Assets.car")))
      large = renditions.any? do |entry|
        entry.is_a?(Hash) && entry["AssetType"] == "Icon Image" && entry["Name"] == "AppIcon" && entry["PixelWidth"] == 1024
      end
      problems = []
      problems << "Assets.car has no 1024 pixel AppIcon image, which the App Store shows" unless large
      png = File.join(@project, "Host", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
      problems << "#{png} has an alpha channel, which App Store Connect refuses in an app icon (ITMS-90717)" if File.file?(png) && IOSArchive.alpha?(png)
      problems
    end

    private def capture(*command)
      out, status = Open3.capture2(*command)
      raise "#{command.join(' ')} failed" unless status.success?

      out
    end
  end
end
