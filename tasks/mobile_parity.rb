# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require_relative "parity"

# The parity check on a phone (ADR 011, section 6): the parity probe
# (test/fixtures/parity/main.rb), run by a mobile runtime in the iOS
# Simulator or an Android emulator, against the same main.rb under the
# desktop Ruby of the computer that runs the simulator (rv-ruby's, as
# the desktop parity check runs it), and a script that requires json and
# csv, a bundled gem (test/fixtures/mobile/app/hello.rb).
#
# Each runs in a small host app, CI's own and no part of a runtime
# (test/fixtures/mobile/ios and android), which starts Ruby through the
# embedding API with the script its launch names, and whose output
# reaches the check the way an app's reaches its developer: through the
# system log the embedding API forwards it to (os_log, logcat). The
# report is one long line, which the log holds as several entries in a
# row (MobileParity.report). Every difference from the desktop Ruby is
# justified in Parity::JUSTIFIED for the mobile targets, or fails.
#
#   ruby tasks/mobile_parity.rb ios RUNTIME_ARCHIVE
#   ruby tasks/mobile_parity.rb android-build RUNTIME_ARCHIVE
#   ruby tasks/mobile_parity.rb android APK
class MobileParity
  ROOT = Parity::ROOT
  FIXTURES = File.join(ROOT, "test", "fixtures", "mobile")

  # The host apps' identifier, which is also their log's tag.
  IDENTIFIER = "org.setdef.fledge.parity"

  # What hello.rb prints, when the runtime keeps csv a gem and can reach
  # a server over HTTPS with the CA certificates it carries.
  HELLO = /\AHello from Ruby 4\.0\.9 on \S+: \["csv","\d+\.\d+\.\d+"\] over HTTPS: 200\z/

  # The line a host app writes, after Ruby returns, with Ruby's status.
  STATUS = /\AFLEDGE-MOBILE-STATUS (-?\d+)\z/

  # The probe's report, from the system log's +entries+ (its lines, in
  # order): the entry that begins it, joined with those after it up to
  # where they make a JSON object.
  def self.report(entries)
    start = entries.index { |entry| entry.start_with?("FLEDGE-PARITY ") } or raise "the probe printed no report"
    text = +""
    entries.drop(start).each do |entry|
      text << entry
      begin
        return JSON.parse(text.delete_prefix("FLEDGE-PARITY "))
      rescue JSON::ParserError
        next
      end
    end
    raise "the probe's report ends before it is whole: #{text[-200..]}"
  end

  # The status a host app reported Ruby exited with, or nil before it
  # has.
  def self.status(entries)
    entries.reverse_each { |entry| return Integer(entry[STATUS, 1]) if entry.match?(STATUS) }
    nil
  end

  # The environment the reference Ruby runs main.rb in: a person's,
  # with a UTF-8 locale, a home folder of its own in +work+, and the
  # caller's PATH, but nothing of the caller's own Ruby, and none of
  # the runner's other settings, which the phone's app does not see
  # either.
  def self.reference_environment(work, env = ENV.to_h)
    { "PATH" => env.fetch("PATH"), "HOME" => File.join(work, "home"), "LANG" => "en_US.UTF-8" }
  end

  def initialize(target:, work: File.join(ROOT, "tmp", "mobile-parity"), out: $stdout)
    @target = target
    @work = File.expand_path(work)
    @out = out
  end

  # Compares the probe's +report+ from the phone with the reference
  # Ruby's, for the device named +device+, prints and records the
  # differences, and returns whether every one is justified.
  def compare(report, device)
    reference = reference_report
    differences = Parity::Reports.compare(Parity::Reports.normalize(reference, work: @work),
      Parity::Reports.normalize(report, work: @work), platform: @target)
    lines = [
      "Parity on #{@target} (#{device}) with ruby main.rb on #{desktop}: #{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      *differences.map(&:to_s),
    ]
    @out.puts lines
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
    differences.all?(&:justified?)
  end

  # Checks hello.rb's output, from the log's +entries+.
  def check_hello(entries, device)
    line = entries.find { |entry| entry.start_with?("Hello from Ruby") }
    raise "hello.rb printed no greeting on #{device}:\n#{entries.join("\n")}" unless line
    raise "hello.rb on #{device} printed #{line.inspect}, which does not match #{HELLO.source}" unless line.match?(HELLO)

    @out.puts "#{device}: #{line}"
  end

  # The desktop platform whose Ruby the reference is: the one this
  # computer runs.
  private def desktop
    Fledge::Platform.local
  end

  # The probe's report under the pinned desktop Ruby of this computer,
  # run as ruby main.rb from a copy of the probe's folder, with no
  # arguments, as the host app passes none.
  private def reference_report
    @reference_report ||= begin
      builder = RuntimeBuilder.new(platform: desktop)
      pin = builder.sources.fetch("ruby").fetch("platforms").fetch(desktop.name)
      archive = builder.fetch(pin.fetch("url"), pin.fetch("sha256"))
      into = File.join(@work, "reference")
      FileUtils.rm_rf(into)
      FileUtils.mkdir_p([into, File.join(@work, "home")])
      system("tar", "-xzf", archive, "-C", into, exception: true)
      ruby = Dir.glob(File.join(into, "**", "bin", "ruby")).first or raise "#{archive} holds no ruby"
      app = File.join(@work, "reference-app")
      FileUtils.rm_rf(app)
      FileUtils.cp_r(Parity::PROBE, app)
      out, err, status = Open3.capture3(MobileParity.reference_environment(@work), ruby, "main.rb", chdir: app, unsetenv_others: true)
      raise "ruby main.rb failed (#{status}):\n#{out}\n#{err}" unless status.success?

      Parity::Reports.report(out)
    end
  end
end

require_relative "mobile_parity/ios"
require_relative "mobile_parity/android"

if $PROGRAM_NAME == __FILE__
  command, path = ARGV
  passed = case command
  when "ios" then MobileParity::IOS.new(runtime: path).call
  when "android-build" then MobileParity::Android.build(runtime: path)
  when "android" then MobileParity::Android.new(apk: path).call
  else abort "usage: ruby tasks/mobile_parity.rb ios RUNTIME | android-build RUNTIME | android APK"
  end
  exit(passed ? 0 : 1)
end
