# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "json"
require "open3"

class MobileParity
  # A new iOS Simulator device of the check's own, booting in the
  # background.
  #
  # A simulator takes minutes to boot on a CI runner, about six for the
  # iPad in run 41649344171, and the check used to boot the iPad only
  # once the iPhone was done with. The check now starts both booting once
  # its apps are built, and runs the iPhone's apps while the iPad boots.
  # It does not boot them while the apps build: in run 41685351197, two
  # first boots beside xcodebuild on the runner's three cores made the
  # device builds take 13 minutes instead of under 2, more than the boots
  # saved (doc/contributors/research/2026-11-03-ci-speed.md, section 4).
  #
  # Each device is created for the check alone and deleted after it, so
  # no state is shared with another run's devices or with the ones Xcode
  # set up. CoreSimulator boots several devices at once, as Xcode's
  # parallel testing does with its clones; what two cost is memory, so
  # the check deletes each device as soon as its apps have run.
  class Simulator
    # The device did not boot.
    class NotBooted < StandardError; end

    # The device's UDID, and a name that says which device and iOS it is.
    attr_reader :udid, :name

    # Creates a device of +family+ ("iPhone" or "iPad") for the newest iOS
    # runtime and starts booting it, logging to a file in +work+.
    def self.boot(family, work:)
      runtime, device_type = newest(family)
      udid = capture("xcrun", "simctl", "create", "fledge-mobile-#{family}", device_type, runtime).strip
      new(udid, "#{family} (#{device_type.split('.').last}, #{runtime.split('.').last})", File.join(work, "boot-#{family}.log"))
    end

    # The newest available iOS runtime, and a device type of +family+
    # for it: that of the first simulator of the family Xcode set up for
    # the runtime, which is a current model, or else the last the runtime
    # supports.
    def self.newest(family)
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

    def self.capture(*command)
      out, status = Open3.capture2(*command)
      raise "#{command.join(' ')} failed" unless status.success?

      out
    end

    # Starts simctl bootstatus -b, which boots the device +udid+ and
    # ends once it has booted, writing what it says to +log+.
    def initialize(udid, name, log)
      @udid = udid
      @name = name
      @log = log
      @boot = Process.spawn("xcrun", "simctl", "bootstatus", udid, "-b", out: log, err: [:child, :out])
      @booted = nil
    end

    # Whether the device is still booting.
    def booting?
      return false unless @booted.nil?

      finished = Process.wait2(@boot, Process::WNOHANG)
      @booted = finished.last.success? if finished
      @booted.nil?
    end

    # Waits until the device has booted. Raises NotBooted if it did not.
    def wait
      @booted = Process.wait2(@boot).last.success? if @booted.nil?
      raise NotBooted, "#{@name} did not boot:\n#{File.exist?(@log) ? File.read(@log) : 'it said nothing'}" unless @booted

      self
    end

    # Stops the boot if it is still going, then shuts the device down and
    # deletes it. Safe to call more than once.
    def delete
      if booting?
        Process.kill("TERM", @boot)
        Process.wait2(@boot)
        @booted = false
      end
      system("xcrun", "simctl", "shutdown", @udid, out: File::NULL, err: File::NULL)
      system("xcrun", "simctl", "delete", @udid, out: File::NULL, err: File::NULL)
    end
  end
end
