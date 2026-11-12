# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"
require_relative "ios_archive"

class MobileParity
  # The check in the iOS Simulator, on an iPhone and an iPad: each app's
  # Xcode project, as fledge build ios writes it, built with xcodebuild
  # for the Simulator, and archived for devices, unsigned (IOSArchive), to
  # show that the device slice links, that the archive is the one App
  # Store Connect takes as far as no account shows, and that the privacy
  # manifest names a category for every API Apple asks a reason for that
  # the app's executable imports (PRIVACY_APIS); then, on a new simulator of each kind, each app
  # installed and launched with simctl, its os_log read with log show.
  class IOS
    # The kinds of device the check runs on: an iPhone and an iPad, the
    # newest of each the newest iOS runtime supports.
    FAMILIES = %w[iPhone iPad].freeze

    # How long an app may take, from launch to its status.
    TIMEOUT = 300

    # The platform the Simulator's apps run on, as Parity::JUSTIFIED and
    # RubySpec::JUSTIFIED name it.
    TARGET = "arm64-ios-simulator"

    # The C functions Apple requires a reason for in an app's privacy
    # manifest, by the category the manifest names them under, from
    # "Describing use of required reason API" (developer.apple.com, read
    # 2026-10-28): the file timestamp, system boot time, and disk space
    # APIs that are C functions. The rest are Foundation's and UIKit's,
    # which Ruby does not call. Apple lists getattrlist, fgetattrlist, and
    # getattrlistat among the disk space APIs too, but they are not here
    # under disk space: Ruby's dir.c calls them for the filesystem's type,
    # not for free space, and this check matches by function name only, so
    # listing them would demand a disk space declaration Ruby does not
    # need.
    PRIVACY_APIS = {
      "NSPrivacyAccessedAPICategoryFileTimestamp" => %w[stat fstat fstatat lstat getattrlist fgetattrlist getattrlistat getattrlistbulk],
      "NSPrivacyAccessedAPICategorySystemBootTime" => %w[mach_absolute_time],
      "NSPrivacyAccessedAPICategoryDiskSpace" => %w[statfs statvfs fstatfs fstatvfs],
    }.freeze

    # The reason Fledge's manifest gives for each category it declares
    # (lib/fledge/templates/ios/Host/PrivacyInfo.xcprivacy): C617.1, files
    # inside the app's container, and 35F9.1, time elapsed between events
    # in the app.
    REASONS = {
      "NSPrivacyAccessedAPICategoryFileTimestamp" => "C617.1",
      "NSPrivacyAccessedAPICategorySystemBootTime" => "35F9.1",
    }.freeze

    # The categories of REASONS that the privacy +manifest+ (a Hash, as
    # plutil converts it to JSON) declares without the reason Fledge
    # expects, as a Hash from category to the reasons it names.
    def self.wrong_reasons(manifest)
      manifest.fetch("NSPrivacyAccessedAPITypes").to_h do |type|
        [type.fetch("NSPrivacyAccessedAPIType"), type.fetch("NSPrivacyAccessedAPITypeReasons", [])]
      end.select { |category, reasons| REASONS.key?(category) && !reasons.include?(REASONS.fetch(category)) }
    end

    def initialize(runtimes:, work: File.join(ROOT, "tmp", "mobile-parity", "ios"), out: $stdout)
      @runtimes = File.expand_path(runtimes)
      @work = File.expand_path(work)
      @out = out
    end

    # Builds each app, runs each on each device, and returns whether every
    # app printed what it should and every difference the probe found is
    # justified.
    def call
      FileUtils.rm_rf(@work)
      FileUtils.mkdir_p(@work)
      projects = MobileParity.projects("ios", runtimes: @runtimes, out: File.join(@work, "projects"))
      projects.each do |app, project|
        icon = Fledge::App.at(File.join(ROOT, app.path)).identity.icon
        device = IOSArchive.new(app:, project:, work: @work, icon: !icon.nil?, out: @out).call
        check_privacy(device, File.join(device, app.name))
      end
      apps = projects.to_h { |app, project| [app, build_app(app, project)] }
      parity = MobileParity.new(target: TARGET, work: @work, out: @out)
      FAMILIES.map { |family| on_simulator(family, apps) { |app, entries, device| parity.check(app, entries, device) } }.all?
    end

    # The app built from +project+ for the Simulator, unsigned, with
    # xcodebuild, which must warn of nothing.
    def build_app(app, project)
      derived = File.join(@work, "derived-#{app.identifier}")
      log = File.join(@work, "xcodebuild-#{app.identifier}-iphonesimulator.log")
      built = system("xcodebuild", "-project", File.join(project, "#{app.name}.xcodeproj"), "-scheme", app.name,
        "-configuration", "Debug", "-sdk", "iphonesimulator", "-derivedDataPath", derived, "build", "CODE_SIGNING_ALLOWED=NO",
        out: log, err: [:child, :out])
      raise "xcodebuild failed for #{app.name}:\n#{File.readlines(log).last(60).join}" unless built

      warnings = File.readlines(log).grep(/\bwarning:/).uniq
      raise "xcodebuild warned building #{app.name}:\n#{warnings.join}" unless warnings.empty?

      File.join(derived, "Build", "Products", "Debug-iphonesimulator", "#{app.name}.app")
    end

    # Fails unless the privacy manifest in the app +bundle+ names each
    # category of PRIVACY_APIS whose functions +executable+ imports, as
    # nm, Apple's own tool, lists them, and gives each category Fledge
    # declares the reason (REASONS) Fledge expects.
    private def check_privacy(bundle, executable)
      imported = capture("xcrun", "nm", "-u", executable).lines.map { |line| line.strip.delete_prefix("_") }
      manifest = capture("plutil", "-convert", "json", "-o", "-", File.join(bundle, "PrivacyInfo.xcprivacy"))
      parsed = JSON.parse(manifest)
      declared = parsed.fetch("NSPrivacyAccessedAPITypes").map { |type| type.fetch("NSPrivacyAccessedAPIType") }
      needed = PRIVACY_APIS.select { |_, functions| functions.intersect?(imported) }
      missing = needed.keys - declared
      raise "#{executable} imports #{needed.slice(*missing)}, whose categories its privacy manifest leaves out" unless missing.empty?

      wrong = IOS.wrong_reasons(parsed)
      raise "#{executable}'s privacy manifest names #{wrong}, without the reasons #{REASONS.slice(*wrong.keys)}" unless wrong.empty?

      @out.puts "#{File.basename(executable)} imports #{needed.values.flatten.intersection(imported).join(', ')}: " \
        "its privacy manifest names #{needed.keys.join(' and ')}"
    end

    # Runs each of +apps+, a Hash from App to its built bundle, on a new
    # simulator of +family+, allowing each +timeout+ seconds, yields
    # each app, the lines it logged, and the device's name to the block
    # that checks them, and returns whether every check passed.
    def on_simulator(family, apps, timeout: TIMEOUT)
      runtime, device_type = newest(family)
      udid = capture("xcrun", "simctl", "create", "fledge-mobile-#{family}", device_type, runtime).strip
      begin
        system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
        name = "#{family} (#{device_type.split('.').last}, #{runtime.split('.').last})"
        apps.map do |app, bundle|
          system("xcrun", "simctl", "install", udid, bundle, exception: true)
          yield app, launch(udid, app, timeout), name
        end.all?
      ensure
        system("xcrun", "simctl", "shutdown", udid, out: File::NULL, err: File::NULL)
        system("xcrun", "simctl", "delete", udid, out: File::NULL, err: File::NULL)
      end
    end

    # The newest available iOS runtime, and a device type of +family+
    # for it: that of the first simulator of the family Xcode set up for
    # the runtime, which is a current model, or else the last the runtime
    # supports.
    private def newest(family)
      runtimes = JSON.parse(capture("xcrun", "simctl", "list", "runtimes", "-j")).fetch("runtimes")
      runtime = runtimes.select { |candidate| candidate["platform"] == "iOS" && candidate["isAvailable"] }
        .max_by { |candidate| Gem::Version.new(candidate.fetch("version")) } or raise "this Mac has no iOS Simulator runtime"
      identifier = runtime.fetch("identifier")
      devices = JSON.parse(capture("xcrun", "simctl", "list", "devices", "available", "-j")).fetch("devices").fetch(identifier, [])
      set_up = devices.map { |device| device.fetch("deviceTypeIdentifier") }
      types = runtime.fetch("supportedDeviceTypes").select { |candidate| candidate["productFamily"] == family }
      type = types.find { |candidate| set_up.include?(candidate.fetch("identifier")) } || types.last or
        raise "#{identifier} supports no #{family}"
      [identifier, type.fetch("identifier")]
    end

    # Launches +app+ on the booted simulator +udid+, and returns the lines
    # its process logged up to its status, and after, until the log
    # settles (MobileParity.settled), as log show
    # reads them from the simulator's unified log. log stream would miss a
    # short program's lines on a slow runner, where it can attach after the
    # program has ended; and the process's ID, which simctl launch prints,
    # keeps an earlier launch's lines out. It fails when the app has not
    # finished in +timeout+ seconds.
    private def launch(udid, app, timeout)
      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      launched = capture("xcrun", "simctl", "launch", "--terminate-running-process", udid, app.identifier)
      pid = Integer(launched[/: (\d+)\s*\z/, 1] || raise("simctl launch printed no process ID: #{launched}"))
      deadline = Time.now + timeout
      until MobileParity.status(messages(udid, since, pid, app))
        if Time.now > deadline
          raise "#{app.name} did not finish in #{timeout} seconds:\n#{messages(udid, since, pid, app).last(40).join("\n")}\n" \
            "#{diagnosis(udid, app)}"
        end

        sleep 5
      end
      MobileParity.settled(interval: 5) { messages(udid, since, pid, app) }
        .tap { system("xcrun", "simctl", "terminate", udid, app.identifier, err: File::NULL) }
    end

    # The messages the process +pid+ logged in the app's subsystem since
    # +since+, in order, kept beside the check's other files.
    private def messages(udid, since, pid, app)
      log = File.join(@work, "#{udid}-#{app.identifier}.ndjson")
      system("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info", "--predicate",
        "subsystem == \"#{app.identifier}\"", out: log, err: File::NULL)
      File.readlines(log).filter_map do |line|
        entry = JSON.parse(line)
        entry["eventMessage"] if entry.is_a?(Hash) && entry["processID"] == pid
      rescue JSON::ParserError
        nil
      end
    end

    # What the simulator +udid+ says of +app+, for one that never
    # finished: whether it runs, everything its process logged, and the
    # crash reports the Mac holds for it.
    private def diagnosis(udid, app)
      running = Open3.capture2e("xcrun", "simctl", "spawn", udid, "launchctl", "list").first.lines.grep(/#{Regexp.escape(app.identifier)}/)
      logged = Open3.capture2e("xcrun", "simctl", "spawn", udid, "log", "show", "--last", "10m", "--style", "compact", "--predicate",
        "process == \"#{app.name}\"").first.lines.last(80)
      crashes = Dir.glob(File.join(Dir.home, "Library", "Logs", "DiagnosticReports", "#{app.name}*"))
      crashes.each { |crash| FileUtils.cp(crash, @work) }
      [
        "The app's process: #{running.empty? ? 'not running' : running.join.strip}",
        "What its process logged:",
        *logged,
        "Crash reports: #{crashes.empty? ? 'none' : crashes.join(', ')}",
      ].join("\n")
    end

    private def capture(*command)
      out, status = Open3.capture2(*command)
      raise "#{command.join(' ')} failed" unless status.success?

      out
    end
  end
end
