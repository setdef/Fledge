# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require "json"
require "tmpdir"
require "stringio"
require "fledge/phone_run"

# How fledge test follows an app on a Simulator or emulator: what
# it prints of the app's log, and that the program's status comes only
# from the host's line. test/integration/phone_test_command_test.rb runs
# it on a Simulator and an emulator.
class PhoneRunTest < Minitest::Test
  Line = Fledge::PhoneRun::Line
  Logged = Fledge::PhoneRun::Logged

  # A device whose log is +reads+, one Logged a read, the last again
  # once they run out, and whose process runs while +running+ has a true
  # left.
  class Device
    attr_reader :name, :stopped

    def initialize(reads, running: [true])
      @name = "Basket"
      @reads = reads
      @running = running
      @stopped = false
    end

    def logged
      (@reads.size > 1) ? @reads.shift : @reads.first
    end

    def running?
      (@running.size > 1) ? @running.shift : @running.first
    end

    def stop
      @stopped = true
    end
  end

  def follow(device)
    out = StringIO.new
    err = StringIO.new
    status = Fledge::PhoneRun.new(out:, err:, interval: 0, sleeper: -> (_) {}).follow(device)
    [status, out.string, err.string]
  end

  def test_it_prints_each_line_once_as_it_comes_and_returns_the_status_the_host_logged
    first = [Line.new(text: "Run options: --seed 1", error: false)]
    more = [*first, Line.new(text: "oops", error: true), Line.new(text: "1 runs, 1 failures", error: false)]
    device = Device.new([Logged.new(lines: first, status: nil), Logged.new(lines: more, status: 1)])

    status, out, err = follow(device)

    assert_equal 1, status
    assert_equal "Run options: --seed 1\n1 runs, 1 failures\n", out
    assert_equal "oops\n", err
    assert device.stopped, "the app is stopped once its program has ended"
  end

  def test_it_reads_the_lines_that_reach_the_log_after_the_hosts
    early = [Line.new(text: "a", error: false)]
    later = [*early, Line.new(text: "1 runs", error: false)]
    last = [*later, Line.new(text: "0 failures", error: false)]
    device = Device.new([Logged.new(lines: early, status: 0), Logged.new(lines: later, status: 0), Logged.new(lines: last, status: 0)])

    status, out, = follow(device)

    assert_equal 0, status
    assert_equal "a\n1 runs\n0 failures\n", out, "it reads until two reads are the same"
  end

  def test_a_process_that_ends_without_the_hosts_line_fails_whatever_it_printed
    lines = [Line.new(text: "0 failures, 0 errors", error: false)]
    device = Device.new([Logged.new(lines:, status: nil)], running: [true, false])

    error = assert_raises(Fledge::Error) { follow(device) }

    assert_match(/Basket ended without logging its program's exit status/, error.message)
  end

  def test_a_status_logged_as_the_process_ends_is_read
    device = Device.new([Logged.new(lines: [], status: nil), Logged.new(lines: [], status: 3)], running: [false])

    assert_equal 3, follow(device).first
  end

  def test_the_status_is_read_from_the_hosts_line_for_the_app_alone
    assert_equal 0, Fledge::PhoneRun.status("Basket", "Basket exited with status 0")
    assert_equal(-1, Fledge::PhoneRun.status("Basket", "Basket exited with status -1"))
    assert_nil Fledge::PhoneRun.status("Basket", "Hello exited with status 0")
    assert_nil Fledge::PhoneRun.status("Basket", "Basket exited with status 0 and more")
  end

  def ndjson(*entries)
    ["Filtering the log data using \"subsystem == ...\"", *entries.map { |entry| JSON.generate(entry) }].join("\n")
  end

  def test_ios_reads_its_process_lines_and_takes_the_status_from_the_hosts_category_alone
    log = ndjson(
      { "processID" => 7, "category" => "ruby", "messageType" => "Default", "eventMessage" => "Basket exited with status 0" },
      { "processID" => 7, "category" => "ruby", "messageType" => "Error", "eventMessage" => "a warning" },
      { "processID" => 8, "category" => "app", "messageType" => "Default", "eventMessage" => "Basket exited with status 0" },
      { "processID" => 7, "category" => "app", "messageType" => "Default", "eventMessage" => "Basket exited with status 1" },
    )

    logged = Fledge::PhoneRun::IOS.read(log, 7, "Basket")

    assert_equal 1, logged.status
    assert_equal [Line.new(text: "Basket exited with status 0", error: false), Line.new(text: "a warning", error: true)], logged.lines
  end

  def test_ios_runs_on_the_one_booted_simulator
    booted = { "state" => "Booted", "udid" => "U1", "name" => "iPhone 17" }
    list = -> (*devices) { JSON.generate("devices" => { "com.apple.CoreSimulator.SimRuntime.iOS-27-0" => devices }) }

    assert_equal "U1", Fledge::PhoneRun::IOS.booted(list.call(booted, { "state" => "Shutdown", "udid" => "U2", "name" => "iPad" }))
    assert_match(/No Simulator is booted/, assert_raises(Fledge::Error) { Fledge::PhoneRun::IOS.booted(list.call) }.message)
    two = assert_raises(Fledge::Error) { Fledge::PhoneRun::IOS.booted(list.call(booted, booted.merge("udid" => "U3", "name" => "iPad"))) }
    assert_match(/2 Simulators are booted \(iPhone 17, iPad\)/, two.message)
  end

  def test_android_reads_its_tags_lines_and_the_hosts_status
    log = [
      "--------- beginning of main",
      "I/com.example.Basket: Run options: --seed 1",
      "W/com.example.Basket: a warning",
      "I/com.example.Basket: before\xC0\x80after".b,
      "I/ActivityManager: Basket exited with status 0",
      "I/com.example.Basket.host: Basket exited with status 1",
    ].join("\n")

    logged = Fledge::PhoneRun::Android.read(log, "com.example.Basket", "Basket")

    assert_equal 1, logged.status
    assert_equal [
      Line.new(text: "Run options: --seed 1", error: false),
      Line.new(text: "a warning", error: true),
      Line.new(text: "before\0after", error: false),
    ], logged.lines
  end

  def test_android_takes_a_status_from_the_hosts_information_alone
    logged = Fledge::PhoneRun::Android.read("W/com.example.Basket.host: Basket exited with status 0\n", "com.example.Basket", "Basket")

    assert_nil logged.status
    assert_equal [Line.new(text: "Basket exited with status 0", error: true)], logged.lines
  end

  def test_android_takes_no_status_from_what_the_program_prints
    log = [
      "I/com.example.Basket: Basket exited with status 0",
      "I/com.example.Basket: 1 failure",
      "I/com.example.Basket.host: Basket exited with status 1",
    ].join("\n")
    printed = Fledge::PhoneRun::Android.read(log.lines.first, "com.example.Basket", "Basket")
    ended = Fledge::PhoneRun::Android.read(log, "com.example.Basket", "Basket")

    assert_nil printed.status
    assert_equal [Line.new(text: "Basket exited with status 0", error: false)], printed.lines
    assert_equal 1, ended.status
    assert_equal ["Basket exited with status 0", "1 failure"], ended.lines.map(&:text)
  end

  # The stand-in adb is a .cmd file on Windows, which cmd.exe runs, and
  # a shell script elsewhere, as test/support/stand_in_signer.rb does.
  def test_android_asks_logcat_for_the_apps_tag_and_the_hosts
    Dir.mktmpdir do |dir|
      asked = File.join(dir, "asked")
      adb = File.join(dir, Gem.win_platform? ? "adb.cmd" : "adb")
      if Gem.win_platform?
        File.binwrite(adb, "@echo off\r\necho %*>\"#{asked}\"\r\n")
      else
        File.write(adb, "#!/bin/sh\necho \"$@\" > \"#{asked}\"\n")
      end
      File.chmod(0o755, adb)
      Fledge::PhoneRun::Android.new(name: "Basket", identifier: "com.example.Basket", adb:).logged

      assert_equal "logcat -d -v tag -s com.example.Basket:V com.example.Basket.host:V\n", File.read(File.join(dir, "asked"))
    end
  end
end
