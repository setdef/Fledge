# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "error"

module Fledge
  # Follows a phone app as it runs on an iOS Simulator or an Android
  # emulator, prints what its program prints, and answers the program's
  # exit status, for <tt>fledge test</tt>.
  #
  # A phone app's program writes to the system log, not to a terminal
  # (doc/contributors/design/phone-runtimes.md, "Output to the system
  # log"), and the app outlives it, so nothing waits on the program the
  # way a shell waits on <tt>ruby test.rb</tt>. What does tell a reader
  # the program has ended is the line every host Fledge writes logs once
  # it has: <tt>NAME exited with status N</tt>. Briefcase's
  # <tt>briefcase run iOS --test</tt> reads a test suite's result the same
  # way, from a line its app logs at the end, and fails a run that
  # logged none ("Test suite didn't report a result").
  #
  # This class reads the app's log over and over, through a device
  # (PhoneRun::IOS or PhoneRun::Android) that knows the system's log, and
  # prints each new line as it comes, standard error's to the error
  # stream. Once the host's line is there it reads until the log stops
  # growing, since the program's last lines may reach the log after the
  # host's, stops the app, and answers the status. The status comes only
  # from that line, so a line the log drops never passes a program that
  # failed: without the host's line there is no status, and a process
  # that ended without one is an error.
  #
  # Use it from <tt>fledge test</tt>.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   device = Fledge::PhoneRun::IOS.new(name: "Basket", identifier: "com.example.Basket", udid: "...")
  #   device.launch("dist/test/Basket-ios/DerivedData/.../Basket.app")
  #   Fledge::PhoneRun.new(out: $stdout, err: $stderr).follow(device) # => 0
  #--
  # SPDX-SnippetEnd
  #++
  class PhoneRun
    # A line the app logged: its +text+, and whether it came from
    # standard error (+error+).
    class Line < Data.define(:text, :error)
    end

    # What the app has logged since it was launched: its +lines+, in
    # order, and the +status+ the host logged when the program ended, or
    # +nil+ before it has.
    class Logged < Data.define(:lines, :status)
    end

    # What the host logs when the app's program ends, after the app's
    # name: lib/fledge/templates/ios/Host/main.m and
    # android/src/main/java/org/setdef/fledge/host/MainActivity.java.
    EXITED = " exited with status "

    # The status the host's line +text+ gives for the app named +name+,
    # or +nil+ when it is no such line.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 setdef <kerrick@setdef.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   Fledge::PhoneRun.status("Basket", "Basket exited with status 1") # => 1
    #--
    # SPDX-SnippetEnd
    #++
    def self.status(name, text)
      digits = text.delete_prefix("#{name}#{EXITED}") if text.start_with?("#{name}#{EXITED}")
      Integer(digits, 10) if digits&.match?(/\A-?\d+\z/)
    end

    # Creates the follower.
    #
    # [out] Where the program's standard output goes, such as
    #       <tt>$stdout</tt>.
    # [err] Where its standard error goes, such as <tt>$stderr</tt>.
    # [interval] The seconds between two reads of the log.
    # [sleeper] What waits +interval+ seconds (default: Kernel#sleep).
    def initialize(out:, err:, interval: 2, sleeper: -> (seconds) { sleep(seconds) })
      @out = out
      @err = err
      @interval = interval
      @sleeper = sleeper
    end

    # Follows the app +device+ launched until the host logs the program's
    # status, printing each line it logged as it comes, then stops the app
    # and returns the status. Raises Fledge::Error when the app's process
    # ends with no status logged, as when the system stopped it.
    def follow(device)
      shown = 0
      loop do
        logged = device.logged
        shown = show(logged.lines, shown)
        return finish(device, logged, shown) if logged.status

        unless device.running?
          logged = device.logged
          shown = show(logged.lines, shown)
          return finish(device, logged, shown) if logged.status

          raise Error, "#{device.name} ended without logging its program's exit status: the system stopped it, or it crashed. " \
            "Its log above says what it printed."
        end
        @sleeper.call(@interval)
      end
    end

    # Reads the log until two reads +interval+ apart are the same, prints
    # what is new, stops the app, and returns +logged+'s status: the
    # system's log may take a moment to show what the app has logged, so
    # the last lines may come after the host's status.
    private def finish(device, logged, shown)
      status = logged.status
      loop do
        @sleeper.call(@interval)
        later = device.logged
        shown = show(later.lines, shown)
        break if later.lines.size == logged.lines.size

        logged = later
      end
      device.stop
      status || 1
    end

    # Prints the +lines+ after the first +shown+, and returns how many
    # are shown.
    private def show(lines, shown)
      lines.drop(shown).each { |line| (line.error ? @err : @out).puts(line.text) }
      [lines.size, shown].max
    end
  end
end

require_relative "phone_run/android"
require_relative "phone_run/ios"
