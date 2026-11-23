# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "parity"

# The mobile check (ADR 012; doc/contributors/design/parity.md, "The mobile
# parity"): apps built as a developer builds them, with fledge build ios
# and fledge build android, their projects built with xcodebuild and
# Gradle, and run in the iOS Simulator, on an iPhone and an iPad, and on
# Android emulators, each app's output read back the way an app's
# reaches its developer: from the system log the embedding API forwards
# it to (os_log, logcat).
#
# The apps (APPS) are examples/hello; examples/mobile_app, whose pure-Ruby
# gems Bundler sets up; test/fixtures/native_phone, whose gem has a C and C++
# extension compiled for the phone
# (doc/contributors/design/phone-projects.md, "Gems with extensions"),
# linked into the app on iOS and a file Ruby loads on Android;
# test/fixtures/cmake_phone, whose gem's
# extconf.rb builds a C++ library with CMake for each of the phone's
# targets (doc/contributors/design/phone-projects.md, "CMake toolchain
# files"), and whose Android host loads the native libraries a host may
# name in a fixed list; examples/rake_phone,
# whose gem from rubygems.org, digest-crc, builds its C extensions from a
# Rakefile, with mkmf, and prints whether they ran; test/fixtures/rust_phone,
# whose gem's Rust extension (rb-sys and magnus) Cargo builds for each of
# the phone's targets (doc/contributors/design/phone-projects.md, "Gems
# with extensions"); examples/ffi_phone, whose ffi gem from
# rubygems.org builds the libffi it bundles and calls C by name, with a
# Ruby block as a callback; examples/ffi_library_phone, whose gems from
# rubygems.org, llhttp-ffi and scrypt, each build a library for ffi to
# open from a Rakefile, which the app carries as a framework of its own
# on iOS and a native library of its own on Android; a script that requires json and csv, a bundled
# gem, parses with prism, a bundled gem whose extension compiles its own
# libprism (doc/contributors/design/phone-runtimes.md, "Bundled gems' extensions"), and
# reaches rubygems.org over HTTPS
# (test/fixtures/mobile_hello); on Android, an app that runs the command
# of a gem its lockfile locks, and no runtime has, by its name
# (test/fixtures/mobile_commands); and the parity probe (test/fixtures/parity), whose report is compared
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
#   ruby tasks/mobile_parity.rb android-bundle AAB
class MobileParity
  ROOT = Parity::ROOT

  # An app the check builds and runs: its project, the name and
  # identifier its fledge.yml gives it, the line it must print, or nil
  # for the parity probe, whose report is compared instead, and the
  # phones it runs on (default: both).
  class App < Data.define(:path, :name, :identifier, :prints, :phones)
    def initialize(path:, name:, identifier:, prints:, phones: %w[ios android])
      super
    end
  end

  # What test/fixtures/mobile_hello prints, when the runtime keeps csv a
  # gem, keeps prism a gem whose extension parses, and can reach a server
  # over HTTPS with the CA certificates it carries; and, on Android, when
  # YJIT, once the app enables it, writes machine code and runs it, where
  # iOS's Ruby has no YJIT.
  HELLO_LIBRARIES = '\["csv","\d+\.\d+\.\d+"\], prism \d+\.\d+\.\d+ parses 1 \+ 2 as \+, over HTTPS: 200'
  HELLO = /\AHello from Ruby 4\.1\.0 on (?:arm64-darwin: #{HELLO_LIBRARIES}, no YJIT|(?:aarch64|x86_64)-linux-android: #{HELLO_LIBRARIES}, YJIT on: fib\(20\) is 6765 in [1-9]\d* bytes of machine code)\z/o

  # The apps, each built with fledge build for each phone.
  APPS = [
    App.new(path: "examples/hello", name: "Hello", identifier: "com.setdef.fledge.Hello",
      prints: /\AHello from Ruby 4\.1\.0 on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z/),
    App.new(path: "examples/mobile_app", name: "Mobile App", identifier: "com.setdef.fledge.MobileApp",
      prints: /\AMobileApp 1\.2\.3 says hello through i18n 1\.15\.2 and concurrent-ruby 1\.3\.8, set up by Bundler\z/),
    App.new(path: "test/fixtures/native_phone", name: "NativePhone", identifier: "com.setdef.fledge.NativePhone",
      prints: /\ANativePhone adds 5 and totals 10 with a C extension \(C and C\+\+\) on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z/),
    App.new(path: "test/fixtures/cmake_phone", name: "CmakePhone", identifier: "com.setdef.fledge.CmakePhone",
      prints: /\ACmakePhone totals 10 in C\+\+ that CMake \d+\.\d+\.\d+ built for (?:iOS(?: Simulator)? on arm64, on arm64-darwin|Android on (?:arm64, on aarch64|x86_64, on x86_64)-linux-android)\z/),
    App.new(path: "examples/rake_phone", name: "RakePhone", identifier: "com.setdef.fledge.RakePhone",
      prints: /\ARakePhone: CRC32 of hello is 3610a686 in C, from digest-crc 0\.7\.0's Rakefile, on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z/),
    App.new(path: "test/fixtures/rust_phone", name: "RustPhone", identifier: "com.setdef.fledge.RustPhone",
      prints: /\ARustPhone totals 10 in Rust built for (?:ios on aarch64, on arm64-darwin|android on (?:aarch64, on aarch64|x86_64, on x86_64)-linux-android)\z/),
    App.new(path: "examples/ffi_phone", name: "FfiPhone", identifier: "com.setdef.fledge.FfiPhone",
      prints: /\AFfiPhone: ffi 1\.17\.4 finds strlen of hello 5 and sorts \[1, 2, 3\] with a Ruby block, on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z/),
    App.new(path: "examples/ffi_library_phone", name: "FfiLibraryPhone", identifier: "com.setdef.fledge.FfiLibraryPhone",
      prints: %r{\AFfiLibraryPhone: llhttp-ffi 0\.5\.1 parses GET /hello, and scrypt 3\.1\.0's key matches RFC 7914, on (?:arm64-darwin|aarch64-linux-android|x86_64-linux-android)\z}),
    App.new(path: "test/fixtures/mobile_hello", name: "MobileHello", identifier: "com.setdef.fledge.MobileHello", prints: HELLO),
    App.new(path: "test/fixtures/mobile_commands", name: "MobileCommands", identifier: "com.setdef.fledge.MobileCommands",
      prints: /\AMobileCommands runs thor by name \(Thor 1\.5\.0\), from a shell \(Thor 1\.5\.0\), and with ruby -S \(Thor 1\.5\.0\), with Bundler's thor 1\.5\.0, on (?:aarch64|x86_64)-linux-android\z/,
      phones: %w[android]),
    App.new(path: "test/fixtures/parity", name: "Parity", identifier: "com.setdef.fledge.Parity", prints: nil),
  ].freeze

  # The line the host app of every project fledge build writes logs when
  # the app's program ends, with its exit status.
  STATUS = / exited with status (-?\d+)\z/

  # What an app logged: every +entries+ (its lines, in order), for
  # reporting its failures to a person, and its +output+ alone, without
  # the lines of standard error, for reading what it printed. The
  # embedding API forwards each stream through a pipe, read by a thread
  # of its own, so a line of standard error can land anywhere among those
  # of standard output, inside a report included (IOS.messages,
  # Android.messages).
  class Logged < Data.define(:entries, :output)
  end

  # The apps of APPS that run on +phone+.
  def self.apps(phone)
    APPS.select { |app| app.phones.include?(phone) }
  end

  # Writes each app's project for +phone+ into +out+ with fledge build,
  # as a developer would, taking the runtime from +runtimes+, and
  # returns each app's project folder: what fledge build prints on
  # standard output, as what it downloads goes to standard error.
  # The runtime is one this checkout built, which its pins do not name,
  # so the build is told so (FLEDGE_RUNTIME_DIR_UNCHECKED).
  def self.projects(phone, runtimes:, out:, apps: self.apps(phone), env: {})
    fledge = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "fledge")]
    apps.to_h do |app|
      own = { "FLEDGE_RUNTIME_DIR" => File.expand_path(runtimes), "FLEDGE_RUNTIME_DIR_UNCHECKED" => "1" }
      printed, logged, status = Open3.capture3(env.merge(own), *fledge, "build", phone,
        "-o", out, File.expand_path(app.path, ROOT), chdir: ROOT)
      raise "fledge build #{phone} #{app.path} failed:\n#{printed}#{logged}" unless status.success?

      project = File.expand_path(printed.strip, ROOT)
      Environment.record(phone, project) unless app.prints
      [app, project]
    end
  end

  # The environment the phone's system gave the parity probe's app,
  # which the probe's ENV is compared with, so that the check sees
  # anything Fledge adds to it, as no desktop's environment could show:
  # a phone starts an app with an environment of its own, which no
  # person's ruby main.rb has. The probe's host logs it, a line for each
  # variable, before it calls anything of Fledge's: the host fledge
  # build writes, but for that loop (Environment.record).
  module Environment
    # What begins each of the host's lines.
    LINE = "FLEDGE-ENVIRON "

    # Each host, by the phone it is for: the file fledge build writes it
    # to in a project, the line before which the loop goes, and the loop.
    HOSTS = {
      "ios" => [
        "Host/main.m",
        "        if (fledge_ruby_forward_output(",
        "        extern char **environ;\n" \
          "        for (char **variable = environ; *variable != NULL; variable++) os_log(log, \"#{LINE}%{public}s\", *variable);\n",
      ],
      "android" => [
        "src/main/java/org/setdef/fledge/host/MainActivity.java",
        "        FledgeRuby.startApp(",
        "        for (String variable : android.system.Os.environ()) Log.i(tag, \"#{LINE}\" + variable);\n",
      ],
    }.freeze

    # Has the host of the project fledge build wrote for +phone+ in
    # +project+ log its environment as it starts.
    def self.record(phone, project)
      file, before, loop = HOSTS.fetch(phone)
      path = File.join(project, file)
      text = File.read(path)
      raise "#{path} no longer has the line #{before.strip}" unless text.scan(before).one?

      File.write(path, text.sub(before, "#{loop}#{before}"))
    end

    # The environment the host logged among +entries+, as a Hash.
    def self.read(entries)
      lines = entries.filter_map { |entry| entry.delete_prefix(LINE) if entry.start_with?(LINE) }
      raise "the probe's host logged no environment" if lines.empty?

      lines.to_h { |line| line.split("=", 2).then { |name, value| [name, value.to_s] } }
    end
  end

  # The log holds no whole report of the probe's: none of its facts can
  # be compared, so none is, and the Android check launches the probe
  # again (Android#check_launch).
  class CutShort < RuntimeError
  end

  # The probe's report, from the system log's +entries+ (its lines, in
  # order, those of standard output alone, Logged#output): the entry that begins it, joined with those after it up to
  # where they make a JSON object. The host's line with the app's status
  # may come among them, since the host logs it from Ruby's thread while
  # the embedding API's thread is still logging what Ruby printed, so it
  # is left out. Without a whole report it raises CutShort.
  def self.report(entries)
    start = entries.index { |entry| entry.start_with?("FLEDGE-PARITY ") } or raise CutShort, "the probe printed no report"
    text = +""
    entries.drop(start).grep_v(STATUS).each do |entry|
      text << entry
      begin
        return JSON.parse(text.delete_prefix("FLEDGE-PARITY "))
      rescue JSON::ParserError
        next
      end
    end
    raise CutShort, "the probe's report ends before it is whole: #{text[-200..]}"
  end

  # The status a host app reported Ruby exited with, or nil before it
  # has.
  def self.status(entries)
    entries.reverse_each { |entry| return Integer(entry[STATUS, 1]) if entry.match?(STATUS) }
    nil
  end

  # What the block reads of a log, once two reads +interval+ seconds
  # apart are the same, or after +limit+ seconds. The host logs the
  # app's status from Ruby's thread while the embedding API's thread may
  # still be logging what Ruby printed last (MobileParity.report), which
  # for a long last burst, as MSpec's summary at the end of a run, takes
  # longer than a moment on a slow emulator.
  def self.settled(interval: 2, limit: 120)
    deadline = Time.now + limit
    last = yield
    loop do
      sleep interval
      current = yield
      return current if current == last || Time.now > deadline

      last = current
    end
  end

  # The names of a UTF-8 locale the reference Ruby tries, in order:
  # en_US.UTF-8, which macOS, most Linux desktops, and CI's runners
  # have, then those Fledge's runtime tries (runtime/launcher/locale.c),
  # of which a stock Ubuntu or a container that generated no locale has
  # C.UTF-8 alone. Ruby sets only LC_CTYPE from the environment (main.c,
  # line 58, at Ruby 4.1.0-preview1), so the name changes nothing the
  # reference shows but the character set, which is UTF-8 under each.
  REFERENCE_LOCALES = %w[en_US.UTF-8 C.UTF-8 C.utf8 UTF-8].freeze

  # The first of REFERENCE_LOCALES this computer has, asked of +ruby+,
  # the reference Ruby: the first under which its
  # Encoding.locale_charmap is UTF-8, as the block, if given, reports
  # it for a LANG. With none, stock Ruby would read every path and
  # argument as US-ASCII, and the check would report that as the
  # phone's difference, so it stops and says so.
  def self.reference_locale(ruby, &charmap)
    charmap ||= lambda do |name|
      IO.popen({ "LANG" => name }, [ruby, "--disable-gems", "-e", "print Encoding.locale_charmap"], unsetenv_others: true, &:read)
    end
    REFERENCE_LOCALES.find { |name| charmap.call(name).casecmp?("UTF-8") } or
      raise "this computer has no UTF-8 locale: #{ruby} reads text as UTF-8 under none of LANG=#{REFERENCE_LOCALES.join(', ')}. " \
        "Generate one, such as C.UTF-8, for the reference Ruby to run in as a person's Ruby does"
  end

  # The environment the reference Ruby, +ruby+, runs main.rb in: a
  # person's, with the UTF-8 locale +locale+, a home folder of its own
  # in +work+, and the caller's PATH with that Ruby's bin folder first,
  # as a developer's shell has it (Parity#developer), but nothing else
  # of the caller's own Ruby, and none of the runner's other settings,
  # which the phone's app does not see either.
  def self.reference_environment(work, locale, ruby, env = ENV.to_h)
    { "PATH" => [File.dirname(ruby), env.fetch("PATH")].join(File::PATH_SEPARATOR), "HOME" => File.join(work, "home"), "LANG" => locale }
  end

  # The differences between the phone's +report+ and the +reference+
  # Ruby's on +platform+, both normalized with +work+, ENV and a child's
  # taken from +environment+, the one the phone gave the app
  # (Environment), in place of the reference's. On Android that
  # environment's PATH has the app's Ruby's bin folder first, where the
  # runtime puts it as a developer's shell has the Ruby they run
  # (doc/contributors/design/phone-runtimes.md, "Gem commands on
  # Android").
  def self.differences(reference, report, environment, platform:, work:)
    paths = report.fetch("paths")
    if Parity::ANDROID.include?(platform)
      environment = environment.merge("PATH" => [File.join(paths.fetch("prefix"), "bin"), environment["PATH"]].compact.join(":"))
    end
    given = Parity::Reports.normalize({ "paths" => paths, "ENV" => environment }, work:).fetch("ENV")
    skipped = Parity::IOS.include?(platform) ? NOT_YET : []
    expected = Parity::Reports.normalize(reference, work:).merge("ENV" => given, "child ENV" => given).except(*skipped)
    Parity::Reports.compare(expected, Parity::Reports.normalize(report, work:).except(*skipped), platform:)
  end

  # Facts of the probe's that iOS does not yet compare. "gem commands"
  # runs ruby and a gem's command by name, which iOS lets no app do
  # (doc/contributors/design/parity.md, "The probe").
  NOT_YET = ["gem commands"].freeze

  def initialize(target:, work: File.join(ROOT, "tmp", "mobile-parity"), out: $stdout)
    @target = target
    @work = File.expand_path(work)
    @out = out
  end

  # Compares the probe's +report+ from the phone with the reference
  # Ruby's, for the device named +device+, prints and records the
  # differences, and returns whether every one is justified. Its ENV,
  # and a child's, are compared with +environment+, the one the phone
  # gave the app (Environment), not with the desktop's.
  def compare(report, device, environment:)
    differences = MobileParity.differences(reference_report, report, environment, platform: @target, work: @work)
    lines = [
      "Parity on #{@target} (#{device}) with ruby main.rb on #{desktop}, and with the environment the phone gave the app: " \
        "#{differences.count(&:justified?)} justified, " \
        "#{differences.count { |difference| !difference.justified? }} unjustified differences",
      *differences.map(&:to_s),
    ]
    @out.puts lines
    summary = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
    File.write(summary, "```\n#{lines.join("\n")}\n```\n", mode: "a") if summary
    differences.all?(&:justified?)
  end

  # Checks what +app+ logged on the device named +device+, a Logged:
  # that it exited with status 0 and printed its line, or, for the parity
  # probe, that every difference its report shows, read from its standard
  # output alone, from ruby main.rb's and from the environment its host
  # logged, is justified. A failure reports both streams. Returns
  # whether it passed.
  def check(app, logged, device)
    entries = logged.entries
    status = MobileParity.status(entries)
    raise "#{app.name} on #{device} exited with status #{status}:\n#{entries.last(40).join("\n")}" unless status&.zero?
    return compare(MobileParity.report(logged.output), device, environment: Environment.read(entries)) unless app.prints

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
      archive = builder.fetch_pin(pin)
      into = File.join(@work, "reference")
      FileUtils.rm_rf(into)
      FileUtils.mkdir_p([into, File.join(@work, "home")])
      system("tar", "-xzf", archive, "-C", into, exception: true)
      ruby = Dir.glob(File.join(into, "**", "bin", "ruby")).first or raise "#{archive} holds no ruby"
      app = File.join(@work, "reference-app")
      FileUtils.rm_rf(app)
      FileUtils.cp_r(Parity::PROBE, app)
      out, err, status = Open3.capture3(MobileParity.reference_environment(@work, MobileParity.reference_locale(ruby), ruby), ruby, "main.rb", chdir: app, unsetenv_others: true)
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
  when "android-bundle"
    work = File.join(MobileParity::ROOT, "tmp", "mobile-parity", "android", "bundle")
    MobileParity::Android.check_bundle(path, apks: File.join(work, "app.apks"), work:, out: $stdout) || true
  else abort "usage: ruby tasks/mobile_parity.rb ios RUNTIMES_DIR | android-build RUNTIMES_DIR | android | android-check APK | android-bundle AAB"
  end
  exit(passed ? 0 : 1)
end
