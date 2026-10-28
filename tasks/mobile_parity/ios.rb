# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "tmpdir"

class MobileParity
  # The check in the iOS Simulator, on an iPhone and an iPad, after the
  # spike's ios/build-app.sh and ios/run-sim.sh: the host app
  # (test/fixtures/mobile/ios) built with XcodeGen and xcodebuild for the
  # Simulator from the runtime's XCFramework, and for devices, unsigned,
  # to show that the device slice links; then, on a new simulator of
  # each kind, the app installed and launched with simctl for each
  # script, its os_log read with log stream.
  class IOS
    # The kinds of device the check runs on: an iPhone and an iPad, the
    # newest of each the newest iOS runtime supports.
    FAMILIES = %w[iPhone iPad].freeze

    # How long a script may take, from launch to its status.
    TIMEOUT = 300

    def initialize(runtime:, work: File.join(ROOT, "tmp", "mobile-parity", "ios"), out: $stdout)
      @runtime = File.expand_path(runtime)
      @work = File.expand_path(work)
      @out = out
    end

    # Builds the host app, runs both scripts on each device, and returns
    # whether hello.rb said what it should and every difference the probe
    # found is justified.
    def call
      FileUtils.rm_rf(@work)
      FileUtils.mkdir_p(@work)
      framework = unpack
      device = build_app(framework, "iphoneos")
      @out.puts "Built #{device} for devices, unsigned: #{capture('xcrun', 'vtool', '-show-build', File.join(device, 'FledgeParity'))}"
      app = build_app(framework, "iphonesimulator")
      FAMILIES.map { |family| on_simulator(family, app) }.all?
    end

    private def unpack
      tree = File.join(@work, "runtime")
      FileUtils.mkdir_p(tree)
      system("tar", "-xzf", @runtime, "-C", tree, exception: true)
      Dir.glob(File.join(tree, "*", "FledgeRuby.xcframework")).first or raise "#{@runtime} holds no FledgeRuby.xcframework"
    end

    # The host app built for +sdk+, with the Ruby of the XCFramework's
    # slice for it, as an app copies it into its bundle.
    private def build_app(framework, sdk)
      project = File.join(@work, "host-#{sdk}")
      FileUtils.cp_r(File.join(FIXTURES, "ios"), project)
      staged = File.join(project, "staged")
      slice = File.join(framework, (sdk == "iphoneos") ? "ios-arm64" : "ios-arm64-simulator")
      FileUtils.mkdir_p(File.join(staged, "ruby"))
      FileUtils.cp_r(framework, staged)
      %w[lib libexec].each { |folder| FileUtils.cp_r(File.join(slice, folder), File.join(staged, "ruby", folder)) }
      FileUtils.mkdir_p(File.join(staged, "app"))
      FileUtils.cp(File.join(Parity::PROBE, "main.rb"), File.join(staged, "app"))
      FileUtils.cp(File.join(FIXTURES, "app", "hello.rb"), File.join(staged, "app"))
      system("xcodegen", "generate", "--quiet", "--spec", File.join(project, "project.yml"), exception: true)
      derived = File.join(project, "derived")
      log = File.join(@work, "xcodebuild-#{sdk}.log")
      built = system("xcodebuild", "-project", File.join(project, "FledgeParity.xcodeproj"), "-scheme", "FledgeParity",
        "-configuration", "Release", "-sdk", sdk, "-derivedDataPath", derived, "build", "CODE_SIGNING_ALLOWED=NO",
        out: log, err: [:child, :out])
      raise "xcodebuild failed for #{sdk}:\n#{File.readlines(log).last(60).join}" unless built

      File.join(derived, "Build", "Products", "Release-#{sdk}", "FledgeParity.app")
    end

    # Runs hello.rb and the probe on a new simulator of +family+, and
    # returns whether both passed.
    private def on_simulator(family, app)
      runtime, device_type = newest(family)
      udid = capture("xcrun", "simctl", "create", "fledge-parity-#{family}", device_type, runtime).strip
      begin
        system("xcrun", "simctl", "bootstatus", udid, "-b", out: File::NULL, exception: true)
        system("xcrun", "simctl", "install", udid, app, exception: true)
        name = "#{family} (#{device_type.split('.').last}, #{runtime.split('.').last})"
        MobileParity.new(target: "arm64-ios-simulator", work: @work, out: @out).tap do |parity|
          parity.check_hello(launch(udid, "hello.rb"), name)
          return parity.compare(MobileParity.report(launch(udid, "main.rb")), name)
        end
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

    # Launches the host app on the booted simulator +udid+ with
    # +script+, and returns the lines it logged up to Ruby's status, as
    # log stream gave them.
    private def launch(udid, script)
      log = File.join(@work, "#{udid}-#{script}.ndjson")
      stream = Process.spawn("xcrun", "simctl", "spawn", udid, "log", "stream", "--style", "ndjson", "--level", "info",
        "--predicate", "subsystem == \"#{IDENTIFIER}\"", out: log, err: File::NULL)
      sleep 3
      system("xcrun", "simctl", "launch", "--terminate-running-process", udid, IDENTIFIER, "-FledgeScript", script,
        out: File::NULL, exception: true)
      entries = wait_for_status(log, script)
      @out.puts "#{script}: Ruby exited with status #{MobileParity.status(entries)}"
      raise "#{script} exited with status #{MobileParity.status(entries)}:\n#{entries.last(40).join("\n")}" unless MobileParity.status(entries).zero?

      entries
    ensure
      Process.kill("TERM", stream) if stream
      Process.wait(stream) if stream
    end

    private def wait_for_status(log, script)
      deadline = Time.now + TIMEOUT
      loop do
        entries = messages(log)
        if MobileParity.status(entries)
          sleep 3
          return messages(log)
        end
        raise "#{script} did not finish in #{TIMEOUT} seconds:\n#{entries.last(40).join("\n")}" if Time.now > deadline

        sleep 2
      end
    end

    private def messages(log)
      File.readlines(log).filter_map do |line|
        JSON.parse(line)["eventMessage"]
      rescue JSON::ParserError
        nil
      end
    end

    private def capture(*command)
      out, status = Open3.capture2(*command)
      raise "#{command.join(' ')} failed" unless status.success?

      out
    end
  end
end
