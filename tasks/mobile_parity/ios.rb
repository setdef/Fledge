# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "etc"
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

    # The UI test that types an app's item and presses Return, then
    # swipes its row away (ios_ui/ListUITests/ListTest.m): simctl gives
    # an app no keys or touches, and XCTest, Apple's own UI testing,
    # gives them as a person would.
    UI_TESTS = File.join(__dir__, "ios_ui")

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

    # The folder macOS writes a crashed Simulator app's report into: the
    # account's own home's, wherever HOME points, as ReportCrash writes for
    # the account and not for a process's environment.
    def self.crash_reports
      File.join(Etc.getpwuid.dir, "Library", "Logs", "DiagnosticReports")
    end

    # The messages of the process +pid+ in +ndjson+, what log show
    # --style ndjson prints, in order, without those of standard error
    # unless +standard_error+. The embedding API logs what Ruby writes to
    # standard error as errors, and standard output and the host's own
    # lines as default messages (runtime/mobile/apple.c,
    # fledge_log_write), each stream read by a thread of its own, so the
    # log holds each stream's lines in order but the two interleaved as
    # those threads happen to run (doc/contributors/design/phone-runtimes.md,
    # "Output to the system log").
    def self.messages(ndjson, pid, standard_error: true)
      ndjson.each_line.filter_map do |line|
        entry = JSON.parse(line)
        next unless entry.is_a?(Hash) && entry["processID"] == pid
        next if !standard_error && entry["messageType"] == "Error"

        (message = entry["eventMessage"]) && MobileParity.printed(message, MobileParity::IOS_NUL)
      rescue JSON::ParserError
        nil
      end
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
      @ui_tests = build_ui_tests if apps.keys.any?(&:adds)
      parity = MobileParity.new(target: TARGET, work: @work, out: @out)
      HTTPS.serving(apps.keys) do |url|
        @https_url = url
        FAMILIES.map { |family| on_simulator(family, apps) { |app, logged, device| parity.check(app, logged, device) } }.all?
      end
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
    # category of PRIVACY_APIS whose functions +executable+ or the binary
    # of a framework in the bundle imports, as nm, Apple's own tool, lists
    # them, and gives each category Fledge declares the reason (REASONS)
    # Fledge expects. The app's manifest stands for its frameworks too,
    # which Fledge makes of Ruby, its extensions, and the libraries for
    # Ruby's ffi a gem's build made, all of them the app's own code; only
    # OpenSSL's, a third party's that Apple lists, carries its own
    # (IOSArchive::OPENSSL).
    private def check_privacy(bundle, executable)
      binaries = [executable, *Dir.glob(File.join(bundle, "Frameworks", "*.framework")).map { |folder| File.join(folder, File.basename(folder, ".framework")) }]
      imported = binaries.flat_map { |binary| capture("xcrun", "nm", "-u", binary).lines.map { |line| line.strip.delete_prefix("_") } }.uniq
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
    # each app, what it logged (Logged), and the device's name to the
    # block that checks them, and returns whether every check passed.
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
    # its process logged up to its status (App#finished?), and after, until the log
    # settles (MobileParity.settled), as log show
    # reads them from the simulator's unified log. log stream would miss a
    # short program's lines on a slow runner, where it can attach after the
    # program has ended; and the process's ID, which simctl launch prints,
    # keeps an earlier launch's lines out. It fails when the app has not
    # finished in +timeout+ seconds, and reports both streams.
    private def launch(udid, app, timeout)
      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      # simctl gives an app the variables of its own environment that
      # begin SIMCTL_CHILD_, without the prefix.
      env = app.https ? { "SIMCTL_CHILD_#{HTTPS::VARIABLE}" => @https_url } : {}
      launched = capture("xcrun", "simctl", "launch", "--terminate-running-process", udid, app.identifier, env:)
      pid = Integer(launched[/: (\d+)\s*\z/, 1] || raise("simctl launch printed no process ID: #{launched}"))
      deadline = Time.now + timeout
      until app.finished?(messages(udid, since, pid, app).entries)
        if Time.now > deadline
          raise "#{app.name} did not finish in #{timeout} seconds:\n#{messages(udid, since, pid, app).entries.last(40).join("\n")}\n" \
            "#{diagnosis(udid, app)}"
        end

        sleep 5
      end
      add_and_delete(udid, app) if app.adds
      MobileParity.settled(interval: 5) { messages(udid, since, pid, app) }
        .tap { system("xcrun", "simctl", "terminate", udid, app.identifier, err: File::NULL) }
    end

    # The UI test (UI_TESTS), its Xcode project written by XcodeGen and
    # built for the Simulator once, for every app that adds an item and
    # every simulator: the folder xcodebuild built it in.
    private def build_ui_tests
      project = File.join(@work, "ui-tests")
      FileUtils.rm_rf(project)
      FileUtils.cp_r(UI_TESTS, project)
      system("xcodegen", "generate", "--quiet", "--spec", File.join(project, "project.yml"), "--project", project, exception: true)
      derived = File.join(@work, "derived-ui-tests")
      log = File.join(@work, "xcodebuild-ui-tests.log")
      built = system("xcodebuild", "-project", File.join(project, "ListUITests.xcodeproj"), "-scheme", "ListUITests",
        "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived, "build-for-testing",
        out: log, err: [:child, :out])
      raise "xcodebuild failed for the UI test:\n#{File.readlines(log).last(60).join}" unless built

      derived
    end

    # Does what a person does once +app+ shows its list on the simulator
    # +udid+, with the UI test (UI_TESTS): types the item the app adds
    # into its field, presses Return, waits for its row, and swipes the
    # row left to delete it. Fails with the test's own words when the app
    # does not do as a person expects, and prints what the test did.
    private def add_and_delete(udid, app)
      log = File.join(@work, "ui-test-#{udid}-#{app.identifier}.log")
      env = { "TEST_RUNNER_FLEDGE_APP" => app.identifier, "TEST_RUNNER_FLEDGE_ITEM" => app.adds }
      passed = system(env, "xcodebuild", "-project", File.join(@work, "ui-tests", "ListUITests.xcodeproj"), "-scheme", "ListUITests",
        "-destination", "id=#{udid}", "-derivedDataPath", @ui_tests, "test-without-building", out: log, err: [:child, :out])
      lines = File.readlines(log)
      raise "#{app.name}'s UI test failed:\n#{lines.grep(/error|fail/i).last(20).join}\n#{lines.last(40).join}" unless passed

      lines.grep(/\] (?:Typed|Tapped|Swiped) /).each { |line| @out.puts "#{app.name}: #{line[/(?:Typed|Tapped|Swiped) .*/]}" }
    end

    # The messages the process +pid+ logged in the app's subsystem since
    # +since+, as IOS.messages reads them, the log kept beside the
    # check's other files.
    private def messages(udid, since, pid, app)
      log = File.join(@work, "#{udid}-#{app.identifier}.ndjson")
      system("xcrun", "simctl", "spawn", udid, "log", "show", "--start", since, "--style", "ndjson", "--info", "--predicate",
        "subsystem == \"#{app.identifier}\"", out: log, err: File::NULL)
      ndjson = File.read(log)
      Logged.new(entries: IOS.messages(ndjson, pid), output: IOS.messages(ndjson, pid, standard_error: false))
    end

    # What the simulator +udid+ says of +app+, for one that never
    # finished: whether it runs, everything its process logged, and the
    # crash reports the Mac holds for it.
    private def diagnosis(udid, app)
      running = Open3.capture2e("xcrun", "simctl", "spawn", udid, "launchctl", "list").first.lines.grep(/#{Regexp.escape(app.identifier)}/)
      logged = Open3.capture2e("xcrun", "simctl", "spawn", udid, "log", "show", "--last", "10m", "--style", "compact", "--predicate",
        "process == \"#{app.name}\"").first.lines.last(80)
      crashes = Dir.glob(File.join(IOS.crash_reports, "#{app.name}*"))
      crashes.each { |crash| FileUtils.cp(crash, @work) }
      [
        "The app's process: #{running.empty? ? 'not running' : running.join.strip}",
        "What its process logged:",
        *logged,
        "Crash reports: #{crashes.empty? ? 'none' : crashes.join(', ')}",
      ].join("\n")
    end

    private def capture(*command, env: {})
      out, status = Open3.capture2(env, *command)
      raise "#{command.join(' ')} failed" unless status.success?

      out
    end
  end
end
