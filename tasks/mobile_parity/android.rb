# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"

class MobileParity
  # The check on an Android emulator: each app's Gradle project, as fledge
  # build android writes it, built with its own Gradle wrapper, debug and
  # unsigned release alike, and each APK checked for Play's 16 KB pages and
  # target API; then, on the emulator CI's android-emulator-runner boots,
  # each app installed and started with adb, its logcat read back.
  #
  # GitHub's Linux runners can emulate only x86_64, so the arm64-v8a
  # library is built and checked, but runs on no emulator here.
  class Android
    # How long an app may take, from launch to its status.
    TIMEOUT = 300

    # The host app's activity in every project fledge build writes.
    ACTIVITY = "org.setdef.fledge.host.MainActivity"

    # Where the built debug APKs go, one per app, named for its identifier.
    APKS = File.join(ROOT, "tmp", "mobile-parity", "android", "apks")

    # Writes each app's project from the runtimes in +runtimes+, builds
    # each with Gradle, checks each APK, and keeps each debug APK in APKS.
    def self.build(runtimes:, work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      FileUtils.rm_rf(work)
      FileUtils.mkdir_p(APKS)
      MobileParity.projects("android", runtimes:, out: File.join(work, "projects")).each do |app, project|
        gradlew = File.join(project, Gem.win_platform? ? "gradlew.bat" : "gradlew")
        system(gradlew, "--no-daemon", "--quiet", "--project-dir", project, "assembleDebug", "assembleRelease", exception: true)
        outputs = File.join(project, "build", "outputs", "apk")
        debug = Dir.glob(File.join(outputs, "debug", "*-debug.apk")).first or raise "Gradle built no debug build of #{app.name}"
        release = Dir.glob(File.join(outputs, "release", "*-release-unsigned.apk")).first or raise "Gradle built no unsigned release of #{app.name}"
        [debug, release].each { |apk| check(apk, out) }
        FileUtils.cp(debug, File.join(APKS, "#{app.identifier}.apk"))
        out.puts "Built #{app.name}: #{File.basename(debug)} and #{File.basename(release)}"
      end
      true
    end

    # Play's rules for what the app carries: every native library stored
    # aligned for 16 KB pages (zipalign -c -P 16), and API 36 targeted
    # (aapt2 dump badging), with the Android SDK's own build tools.
    def self.check(apk, out)
      sdk = ENV["ANDROID_HOME"] || ENV["ANDROID_SDK_ROOT"] or raise "the check needs ANDROID_HOME, the Android SDK"
      tools = Dir.glob(File.join(sdk, "build-tools", "*")).max_by { |path| Gem::Version.new(File.basename(path)[/\A[\d.]+/]) }
      aligned, status = Open3.capture2e(File.join(tools, "zipalign"), "-c", "-P", "16", "-v", "4", apk)
      raise "#{apk} is not aligned for 16 KB pages:\n#{aligned}" unless status.success?

      out.puts aligned.lines.grep(/\.so|Verification/).join
      badging = Open3.capture2(File.join(tools, "aapt2"), "dump", "badging", apk).first
      raise "#{apk} does not target API 36 from API 26:\n#{badging}" unless badging.include?("targetSdkVersion:'36'") && badging.include?("minSdkVersion:'26'")

      out.puts badging.lines.grep(/\Apackage:|sdkversion|native-code|application-label:/i).join
    end

    def initialize(work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      @work = File.expand_path(work)
      @out = out
    end

    # Installs each app on the running emulator, runs each, and returns
    # whether every app printed what it should and every difference the
    # probe found is justified.
    def call
      abi = adb("shell", "getprop", "ro.product.cpu.abi").strip
      device = "#{abi} API #{adb('shell', 'getprop', 'ro.build.version.sdk').strip}, #{adb('shell', 'getconf', 'PAGE_SIZE').strip}-byte pages"
      adb("logcat", "-G", "16M")
      parity = MobileParity.new(target: "#{abi.sub('arm64-v8a', 'aarch64')}-linux-android", work: @work, out: @out)
      APPS.map do |app|
        adb("install", "-r", File.join(APKS, "#{app.identifier}.apk"))
        parity.check(app, launch(app), device)
      end.all?
    end

    # Starts +app+ after clearing logcat, and returns the lines it logged
    # up to its status, then stops it, since Ruby boots once per process.
    private def launch(app)
      adb("logcat", "-c")
      adb("shell", "am", "start", "-W", "-n", "#{app.identifier}/#{ACTIVITY}")
      deadline = Time.now + TIMEOUT
      until MobileParity.status(logged(app))
        raise "#{app.name} did not finish in #{TIMEOUT} seconds:\n#{logged(app).last(40).join("\n")}\n#{diagnosis(app)}" if Time.now > deadline

        sleep 2
      end
      sleep 3
      logged(app).tap { adb("shell", "am", "force-stop", app.identifier) }
    end

    # What the emulator says of +app+, for one that never finished:
    # whether its process runs, and logcat's last lines, of every tag,
    # where Android writes why an app did not start or died.
    private def diagnosis(app)
      pid = Open3.capture2e("adb", "shell", "pidof", app.identifier).first.strip
      everything = Open3.capture2e("adb", "logcat", "-d", "-t", "200").first
      File.write(File.join(@work, "logcat-#{app.identifier}.txt"), everything)
      ["The app's process: #{pid.empty? ? 'not running' : pid}", "logcat's last lines:", *everything.lines.last(120)].join("\n")
    end

    # What +app+ logged under its identifier, one entry a line, as logcat
    # -v raw prints them.
    private def logged(app)
      adb("logcat", "-d", "-v", "raw", "-s", "#{app.identifier}:V").lines.map(&:chomp).reject { |line| line.start_with?("--------- ") }
    end

    private def adb(*arguments)
      out, status = Open3.capture2("adb", *arguments)
      raise "adb #{arguments.join(' ')} failed:\n#{out}" unless status.success?

      out
    end
  end
end
