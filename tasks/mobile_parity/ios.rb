# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"

class MobileParity
  # The check in the iOS Simulator, on an iPhone and an iPad: each app's
  # Xcode project, as fledge build ios writes it, built with xcodebuild
  # for the Simulator, and for devices, unsigned, to show that the device
  # slice links and that the privacy manifest names a category for every
  # API Apple asks a reason for that the app's executable imports
  # (PRIVACY_APIS); then, on a new simulator of each kind, each app
  # installed and launched with simctl, its os_log read with log show.
  class IOS
    # The kinds of device the check runs on: an iPhone and an iPad, the
    # newest of each the newest iOS runtime supports.
    FAMILIES = %w[iPhone iPad].freeze

    # How long an app may take, from launch to its status.
    TIMEOUT = 300

    # The C functions Apple requires a reason for in an app's privacy
    # manifest, by the category the manifest names them under, from
    # "Describing use of required reason API" (developer.apple.com, read
    # 2026-10-28): the file timestamp, system boot time, and disk space
    # APIs that are C functions. The rest are Foundation's and UIKit's,
    # which Ruby does not call.
    PRIVACY_APIS = {
      "NSPrivacyAccessedAPICategoryFileTimestamp" => %w[stat fstat fstatat lstat getattrlist fgetattrlist getattrlistat getattrlistbulk],
      "NSPrivacyAccessedAPICategorySystemBootTime" => %w[mach_absolute_time],
      "NSPrivacyAccessedAPICategoryDiskSpace" => %w[statfs statvfs fstatfs fstatvfs],
    }.freeze

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
        device = build_app(app, project, "iphoneos")
        executable = File.join(device, app.name)
        @out.puts "Built #{app.name} for devices, unsigned: #{capture('xcrun', 'vtool', '-show-build', executable).lines.grep(/minos|sdk/).map(&:strip).join(', ')}"
        check_privacy(device, executable)
      end
      apps = projects.to_h { |app, project| [app, build_app(app, project, "iphonesimulator")] }
      FAMILIES.map { |family| on_simulator(family, apps) }.all?
    end

    # The app built from +project+ for +sdk+, unsigned, with xcodebuild,
    # which must warn of nothing.
    private def build_app(app, project, sdk)
      derived = File.join(@work, "derived-#{app.identifier}")
      log = File.join(@work, "xcodebuild-#{app.identifier}-#{sdk}.log")
      configuration = (sdk == "iphoneos") ? "Release" : "Debug"
      built = system("xcodebuild", "-project", File.join(project, "#{app.name}.xcodeproj"), "-scheme", app.name,
        "-configuration", configuration, "-sdk", sdk, "-derivedDataPath", derived, "build", "CODE_SIGNING_ALLOWED=NO",
        out: log, err: [:child, :out])
      raise "xcodebuild failed for #{app.name} (#{sdk}):\n#{File.readlines(log).last(60).join}" unless built

      warnings = File.readlines(log).grep(/\bwarning:/).uniq
      raise "xcodebuild warned building #{app.name} (#{sdk}):\n#{warnings.join}" unless warnings.empty?

      File.join(derived, "Build", "Products", "#{configuration}-#{sdk}", "#{app.name}.app")
    end

    # Fails unless the privacy manifest in the app +bundle+ names each
    # category of PRIVACY_APIS whose functions +executable+ imports, as
    # nm, Apple's own tool, lists them.
    private def check_privacy(bundle, executable)
      imported = capture("xcrun", "nm", "-u", executable).lines.map { |line| line.strip.delete_prefix("_") }
      manifest = capture("plutil", "-convert", "json", "-o", "-", File.join(bundle, "PrivacyInfo.xcprivacy"))
      declared = JSON.parse(manifest).fetch("NSPrivacyAccessedAPITypes").map { |type| type.fetch("NSPrivacyAccessedAPIType") }
      needed = PRIVACY_APIS.select { |_, functions| functions.intersect?(imported) }
      missing = needed.keys - declared
      raise "#{executable} imports #{needed.slice(*missing)}, whose categories its privacy manifest leaves out" unless missing.empty?

      @out.puts "#{File.basename(executable)} imports #{needed.values.flatten.intersection(imported).join(', ')}: " \
        "its privacy manifest names #{needed.keys.join(' and ')}"
    end

    # Runs each app on a new simulator of +family+, and returns whether
    # all passed.
    private def on_simulator(family, apps)
      runtime, device_type = newest(family)
      udid = capture("xcrun", "simctl", "create", "fledge-mobile-#{family}", device_type, runtime).strip
      begin
        system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
        name = "#{family} (#{device_type.split('.').last}, #{runtime.split('.').last})"
        parity = MobileParity.new(target: "arm64-ios-simulator", work: @work, out: @out)
        apps.map do |app, bundle|
          system("xcrun", "simctl", "install", udid, bundle, exception: true)
          parity.check(app, launch(udid, app), name)
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
    # its process logged up to its status, and a moment after, as log show
    # reads them from the simulator's unified log. log stream would miss a
    # short program's lines on a slow runner, where it can attach after the
    # program has ended; and the process's ID, which simctl launch prints,
    # keeps an earlier launch's lines out.
    private def launch(udid, app)
      return launch_with_console(udid, app) unless ENV.fetch("EXPERIMENT_DT_MODE", "").empty?

      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      launched = capture("xcrun", "simctl", "launch", "--terminate-running-process", udid, app.identifier)
      pid = Integer(launched[/: (\d+)\s*\z/, 1] || raise("simctl launch printed no process ID: #{launched}"))
      deadline = Time.now + TIMEOUT
      until MobileParity.status(messages(udid, since, pid, app))
        if Time.now > deadline
          raise "#{app.name} did not finish in #{TIMEOUT} seconds:\n#{messages(udid, since, pid, app).last(40).join("\n")}\n" \
            "#{diagnosis(udid, app)}"
        end

        sleep 5
      end
      sleep 2
      messages(udid, since, pid, app).tap { system("xcrun", "simctl", "terminate", udid, app.identifier, err: File::NULL) }
    end

    # experiment/ios-output: launches +app+ with OS_ACTIVITY_DT_MODE set to
    # EXPERIMENT_DT_MODE, its streams read by simctl launch --console as a
    # developer tool reads them, and returns what the streams carried and
    # what its process logged. Each line the app prints must reach the
    # streams once; the host's status line is logged with os_log.
    private def launch_with_console(udid, app)
      since = (Time.now - 2).strftime("%Y-%m-%d %H:%M:%S")
      console = File.join(@work, "#{udid}-#{app.identifier}.console")
      simctl = Process.spawn({ "SIMCTL_CHILD_OS_ACTIVITY_DT_MODE" => ENV.fetch("EXPERIMENT_DT_MODE") },
        "xcrun", "simctl", "launch", "--console", "--terminate-running-process", udid, app.identifier,
        out: console, err: [:child, :out])
      deadline = Time.now + TIMEOUT
      pid = nil
      until pid && MobileParity.status(messages(udid, since, pid, app))
        # simctl writes its "ID: PID" line to a file only when it exits, so
        # the process's ID comes from launchd in the simulator.
        pid ||= Open3.capture2e("xcrun", "simctl", "spawn", udid, "launchctl", "list").first.lines
          .grep(/UIKitApplication:#{Regexp.escape(app.identifier)}\[/).first&.split&.first&.then { |found| Integer(found, exception: false) }
        if Time.now > deadline
          logged = pid ? messages(udid, since, pid, app) : []
          firsts = logged.first&.then { |first| logged.count { |entry| entry.include?(first) } }
          raise "#{app.name} did not finish in #{TIMEOUT} seconds with OS_ACTIVITY_DT_MODE set: process #{pid.inspect} logged " \
            "#{logged.size} entries, #{firsts.inspect} of them holding its first.\nIts log:\n" \
            "#{logged.first(12).map { |entry| entry[0, 300] }.join("\n")}"
        end

        sleep 5
      end
      sleep 2
      system("xcrun", "simctl", "terminate", udid, app.identifier, err: File::NULL)
      Process.wait(simctl)
      streams = File.readlines(console, chomp: true)
      @out.puts "#{app.name} with OS_ACTIVITY_DT_MODE=#{ENV.fetch('EXPERIMENT_DT_MODE')}, its streams:", *streams.map { |line| "  #{line}" }
      if app.prints && streams.count { |line| line.match?(app.prints) } != 1
        raise "#{app.name} printed its line #{streams.count { |line| line.match?(app.prints) }} times on its streams"
      end

      streams + messages(udid, since, pid, app)
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
