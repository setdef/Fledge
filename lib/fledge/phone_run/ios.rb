# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "json"
require "open3"
require_relative "../command"
require_relative "../error"

module Fledge
  class PhoneRun
    # An iOS app on the booted Simulator, for Fledge::PhoneRun: Xcode's
    # +xcodebuild+ builds the project fledge build ios wrote, for the
    # Simulator, unsigned, and +simctl+ installs and launches the app and
    # reads its unified log, as the mobile parity check does
    # (tasks/mobile_parity/ios.rb).
    #
    # The app's lines are those its process logged under its identifier,
    # the subsystem the host logs under: the runtime's, in the category
    # +ruby+, standard error's as errors, and the host's own, in the
    # category +app+, among them the line with the program's status
    # (lib/fledge/templates/ios/Host/main.m; runtime/mobile/apple.c). So a
    # line the program prints can never be taken for the host's.
    class IOS
      # What a person runs to get Xcode's tools.
      INSTALL = "Install Xcode from the App Store, and run it once."

      # The Simulator's processes are this Mac's, so whether the app runs
      # is asked of this Mac, by default with kill(0).
      ALIVE = lambda do |pid|
        Process.kill(0, pid)
        true
      rescue Errno::EPERM
        true
      rescue Errno::ESRCH
        false
      end

      # Builds the Xcode project +project+ wrote for the app named +name+
      # for the Simulator, unsigned, into the project's own DerivedData,
      # and returns the built app's path. Raises Fledge::Error when
      # xcodebuild fails, with what it printed.
      def self.build(project, name)
        derived = File.join(project, "DerivedData")
        Command.run("xcodebuild", "-project", File.join(project, "#{name}.xcodeproj"), "-scheme", name, "-configuration", "Debug",
          "-sdk", "iphonesimulator", "-derivedDataPath", derived, "build", "CODE_SIGNING_ALLOWED=NO", install: INSTALL)
        File.join(derived, "Build", "Products", "Debug-iphonesimulator", "#{name}.app")
      end

      # The one booted Simulator's UDID, from what <tt>simctl list devices
      # booted -j</tt> printed, +listed+. Raises Fledge::Error when none is
      # booted, or several are, since nothing then says which to run on.
      def self.booted(listed)
        devices = JSON.parse(listed).fetch("devices").values.flatten.select { |device| device["state"] == "Booted" }
        raise Error, "No Simulator is booted. Boot one, such as with open -a Simulator, then run fledge test ios again." if devices.empty?

        if devices.size > 1
          raise Error, "#{devices.size} Simulators are booted (#{devices.map { |device| device.fetch('name') }.join(', ')}): " \
            "shut down all but the one to test on, with xcrun simctl shutdown UDID."
        end

        devices.first.fetch("udid")
      end

      # The lines the process +pid+ logged in +ndjson+, what <tt>log show
      # --style ndjson</tt> printed, and the status the host logged for
      # the app named +name+, as a Fledge::PhoneRun::Logged.
      def self.read(ndjson, pid, name)
        lines = [] # : Array[Line]
        status = nil # : Integer?
        ndjson.each_line do |row|
          process, category, type, text = entry(row)
          next unless process == pid && text

          if category == "app" && (exited = PhoneRun.status(name, text))
            status = exited
          else
            lines << Line.new(text:, error: type == "Error" || category != "ruby")
          end
        end
        Logged.new(lines:, status:)
      end

      # The process, category, type, and message of the entry +row+
      # holds, or +nil+ for a row that holds none, as the lines log show
      # prints before and after its entries.
      private_class_method def self.entry(row)
        parsed = JSON.parse(row)
        return unless parsed.is_a?(Hash)

        process, category, type, text = parsed.values_at("processID", "category", "messageType", "eventMessage")
        [process, category.to_s, type.to_s, text] if process.is_a?(Integer) && text.is_a?(String)
      rescue JSON::ParserError
        nil
      end

      # The app's name, as its host logs it.
      attr_reader :name

      # Creates the device for the app named +name+, whose bundle
      # identifier is +identifier+, on the Simulator +udid+. +alive+ says
      # whether a process runs (default: ALIVE), and +clock+ what time it
      # is (default: Time.now).
      def initialize(name:, identifier:, udid:, alive: ALIVE, clock: -> { Time.now })
        @name = name
        @identifier = identifier
        @udid = udid
        @alive = alive
        @clock = clock
        @pid = 0
        @since = ""
      end

      # Installs the app at +bundle+ and launches it, ending a copy that
      # still runs, since Ruby starts once a process.
      def launch(bundle)
        simctl("install", @udid, bundle)
        @since = (@clock.call - 2).strftime("%Y-%m-%d %H:%M:%S")
        launched = simctl("launch", "--terminate-running-process", @udid, @identifier)
        @pid = Integer(launched[/: (\d+)\s*\z/, 1] || raise(Error, "simctl launch printed no process ID: #{launched}"), 10)
      end

      # What the app's process has logged since its launch.
      def logged
        IOS.read(simctl("spawn", @udid, "log", "show", "--start", @since, "--style", "ndjson", "--info", "--predicate",
          "subsystem == \"#{@identifier}\""), @pid, @name)
      end

      # Whether the app's process still runs.
      def running?
        @alive.call(@pid)
      end

      # Ends the app, if it still runs.
      def stop
        Open3.capture2e("xcrun", "simctl", "terminate", @udid, @identifier)
      end

      private def simctl(*)
        Command.run("xcrun", "simctl", *, install: INSTALL)
      end
    end
  end
end
