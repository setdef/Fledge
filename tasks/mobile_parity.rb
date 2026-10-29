# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "parity"

# The mobile check (ADR 011, section 6; ADR 012): apps built as a
# developer builds them, with fledge build ios and fledge build android,
# their projects built with xcodebuild and Gradle, and run in the iOS
# Simulator, on an iPhone and an iPad, and on Android emulators, each
# app's output read back the way an app's reaches its developer: from the
# system log the embedding API forwards it to (os_log, logcat).
#
# The apps (APPS) are examples/hello; examples/mobile_app, whose pure-Ruby
# gems Bundler sets up; a script that requires json and csv, a bundled
# gem, and reaches rubygems.org over HTTPS (test/fixtures/mobile_hello);
# and the parity probe (test/fixtures/parity), whose report is compared
# with the same main.rb under the desktop Ruby of the computer that runs
# the simulator (rv-ruby's, as the desktop parity check runs it). The
# report is one long line, which the log holds as several entries in a
# row (MobileParity.report). Every difference from the desktop Ruby is
# justified in Parity::JUSTIFIED for the mobile targets, or fails.
#
#   ruby tasks/mobile_parity.rb ios RUNTIMES_DIR
#   ruby tasks/mobile_parity.rb android-build RUNTIMES_DIR
#   ruby tasks/mobile_parity.rb android
#   ruby tasks/mobile_parity.rb android-check APK
class MobileParity
  ROOT = Parity::ROOT

  # An app the check builds and runs: its project, the name and
  # identifier its fledge.yml gives it, and the line it must print, or
  # nil for the parity probe, whose report is compared instead.
  App = Data.define(:path, :name, :identifier, :prints)

  # What test/fixtures/mobile_hello prints, when the runtime keeps csv a
  # gem and can reach a server over HTTPS with the CA certificates it
  # carries.
  HELLO = /\AHello from Ruby 4\.0\.9 on \S+: \["csv","\d+\.\d+\.\d+"\] over HTTPS: 200\z/

  # The apps, each built with fledge build for each phone.
  APPS = [
    App.new(path: "examples/hello", name: "Hello", identifier: "com.setdef.fledge.Hello",
      prints: /\AHello from Ruby 4\.0\.9 on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z/),
    App.new(path: "examples/mobile_app", name: "Mobile App", identifier: "com.setdef.fledge.MobileApp",
      prints: /\AMobileApp 1\.2\.3 says hello through i18n 1\.15\.2 and concurrent-ruby 1\.3\.8, set up by Bundler\z/),
    App.new(path: "test/fixtures/mobile_hello", name: "MobileHello", identifier: "com.setdef.fledge.MobileHello", prints: HELLO),
    App.new(path: "test/fixtures/parity", name: "Parity", identifier: "com.setdef.fledge.Parity", prints: nil),
  ].freeze

  # The line the host app of every project fledge build writes logs when
  # the app's program ends, with its exit status.
  STATUS = / exited with status (-?\d+)\z/

  # Writes each app's project for +phone+ into +out+ with fledge build,
  # as a developer would, taking the runtime from +runtimes+, and
  # returns each app's project folder.
  def self.projects(phone, runtimes:, out:)
    fledge = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "fledge")]
    APPS.to_h do |app|
      printed, status = Open3.capture2e({ "FLEDGE_RUNTIME_DIR" => File.expand_path(runtimes) }, *fledge, "build", phone, "-o", out,
        File.join(ROOT, app.path), chdir: ROOT)
      raise "fledge build #{phone} #{app.path} failed:\n#{printed}" unless status.success?

      [app, File.expand_path(printed.strip, ROOT)]
    end
  end

  # The probe's report, from the system log's +entries+ (its lines, in
  # order): the entry that begins it, joined with those after it up to
  # where they make a JSON object. The host's line with the app's status
  # may come among them, since the host logs it from Ruby's thread while
  # the embedding API's thread is still logging what Ruby printed, so it
  # is left out.
  def self.report(entries)
    start = entries.index { |entry| entry.start_with?("FLEDGE-PARITY ") } or raise "the probe printed no report"
    text = +""
    entries.drop(start).grep_v(STATUS).each do |entry|
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

  # Checks what +app+ logged on the device named +device+, its +entries+:
  # that it exited with status 0 and printed its line, or, for the parity
  # probe, that every difference its report shows is justified. Returns
  # whether it passed.
  def check(app, entries, device)
    status = MobileParity.status(entries)
    raise "#{app.name} on #{device} exited with status #{status}:\n#{entries.last(40).join("\n")}" unless status&.zero?
    return compare(MobileParity.report(entries), device) unless app.prints

    line = entries.find { |entry| entry.match?(app.prints) }
    raise "#{app.name} on #{device} printed no line matching #{app.prints.source}:\n#{entries.join("\n")}" unless line

    @out.puts "#{app.name} on #{device}: #{line}"
    true
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
  when "ios" then MobileParity::IOS.new(runtimes: path).call
  when "android-build" then MobileParity::Android.build(runtimes: path)
  when "android" then MobileParity::Android.new.call
  when "android-check" then MobileParity::Android.check(path, $stdout) || true
  else abort "usage: ruby tasks/mobile_parity.rb ios RUNTIMES_DIR | android-build RUNTIMES_DIR | android | android-check APK"
  end
  exit(passed ? 0 : 1)
end
