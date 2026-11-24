# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "open3"
require_relative "../command"
require_relative "../error"

module Fledge
  class PhoneRun
    # An Android app on the device adb answers for, an emulator or a
    # phone, for Fledge::PhoneRun: the project's Gradle wrapper builds the
    # debug APK of the project fledge build android wrote, and adb
    # installs it, starts its activity, and reads logcat, as the mobile
    # parity check does (tasks/mobile_parity/android.rb). With several
    # devices attached, adb takes the one a serial number, or else
    # +ANDROID_SERIAL+, names.
    #
    # The app's lines are those logged under its identifier, the tag the
    # runtime and the host both log under: standard output's as
    # information, standard error's as warnings (runtime/mobile/android.c),
    # and the host's own, among them the line with the program's status
    # (lib/fledge/templates/android/src/main/java/org/setdef/fledge/host/MainActivity.java).
    # The last line that gives the status is the host's.
    class Android
      # What a person installs to build and run an Android app.
      INSTALL = "Install the Android SDK, with its platform tools, and set ANDROID_HOME to it."

      # The activity of every host fledge build android writes.
      ACTIVITY = "org.setdef.fledge.host.MainActivity"

      # A line of <tt>logcat -v tag</tt>: its priority, its tag, and its
      # message (logprint.cpp's android_log_formatLogLine).
      LINE = %r{\A([VDIWEF])/(.*?) *: ?(.*)\z}

      # What the embedding API logs in place of a NUL byte, which logcat
      # would cut an entry at (runtime/mobile/output.c, NUL_FORM).
      NUL = "\xC0\x80".b

      # Builds the debug APK of the Gradle project +project+ with its own
      # wrapper, and returns its path. Raises Fledge::Error when Gradle
      # fails, with what it printed.
      def self.build(project)
        gradlew = File.join(project, Gem.win_platform? ? "gradlew.bat" : "gradlew")
        Command.run(gradlew, "--project-dir", project, "assembleDebug", install: INSTALL)
        Dir.glob(File.join(project, "build", "outputs", "apk", "debug", "*-debug.apk")).first or
          raise Error, "Gradle built no debug APK in #{project}"
      end

      # The lines logged under +tag+ in +log+, what <tt>logcat -v tag</tt>
      # printed, and the status the host logged for the app named +name+,
      # as a Fledge::PhoneRun::Logged.
      def self.read(log, tag, name)
        lines = [] # : Array[Line]
        status = nil # : Integer?
        log.b.each_line(chomp: true) do |row|
          priority, logged_tag, message = row.match(LINE)&.captures
          next unless priority && message && logged_tag == tag

          text = message.gsub(NUL, "\0".b).force_encoding(Encoding::UTF_8)
          exited = PhoneRun.status(name, text) if priority == "I"
          if exited
            status = exited
          else
            lines << Line.new(text:, error: priority != "I")
          end
        end
        Logged.new(lines:, status:)
      end

      # The adb of the Android SDK at +sdk+, or adb from PATH.
      def self.adb(sdk)
        found = sdk && File.join(sdk, "platform-tools", Gem.win_platform? ? "adb.exe" : "adb")
        (found && File.file?(found)) ? found : "adb"
      end

      # The app's name, as its host logs it.
      attr_reader :name

      # Creates the device for the app named +name+, whose application ID
      # is +identifier+, run with +adb+ on the device whose serial number
      # is +serial+, or adb's own choice when it is +nil+.
      def initialize(name:, identifier:, adb:, serial: nil)
        @name = name
        @identifier = identifier
        @adb = [adb, *(serial ? ["-s", serial] : [])]
        @pid = nil # : String?
      end

      # Installs the APK +apk+ and starts its activity, after ending a copy
      # that still runs, since Ruby starts once a process, and clearing
      # logcat, so that only this launch's lines are read.
      def launch(apk)
        adb("install", "-r", apk)
        adb("shell", "am", "force-stop", @identifier)
        adb("logcat", "-c")
        adb("shell", "am", "start", "-W", "-n", "#{@identifier}/#{ACTIVITY}")
      end

      # What the app has logged since its launch.
      def logged
        Android.read(adb("logcat", "-d", "-v", "tag", "-s", "#{@identifier}:V"), @identifier, @name)
      end

      # Whether the app's process still runs: true until its process is
      # first found, since adb can answer before Android has started it,
      # then whether that process is there.
      def running?
        @pid ||= Open3.capture2e(*@adb, "shell", "pidof", @identifier).first.split.first
        return true unless @pid

        Open3.capture2e(*@adb, "shell", "test", "-d", "/proc/#{@pid}").last.success?
      end

      # Ends the app.
      def stop
        Open3.capture2e(*@adb, "shell", "am", "force-stop", @identifier)
      end

      private def adb(*)
        Command.run(*@adb, *, install: INSTALL)
      end
    end
  end
end
