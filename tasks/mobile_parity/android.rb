# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"

class MobileParity
  # The check on an Android emulator, after the spike's
  # android/build-apk.sh and android/run-emulator.sh: the host app
  # (test/fixtures/mobile/android) built with the pinned Gradle against
  # the runtime's AAR, its asset zipped from the runtime's lib/ and
  # libexec/ and the scripts, and checked for Play's 16 KB pages and
  # target API; then, on the emulator CI's android-emulator-runner
  # boots, the app installed and started with adb for each script, its
  # logcat read back.
  #
  # GitHub's Linux runners can emulate only x86_64, so the arm64-v8a
  # library is built and checked, but runs on no emulator here.
  class Android
    # How long a script may take, from launch to its status.
    TIMEOUT = 300

    # Builds the host app from the runtime archive +runtime+ into
    # tmp/mobile-parity/android/FledgeParity.apk, and checks it.
    def self.build(runtime:, work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      FileUtils.rm_rf(work)
      FileUtils.mkdir_p(work)
      system("tar", "-xzf", File.expand_path(runtime), "-C", work, exception: true)
      tree = Dir.glob(File.join(work, "fledge-runtime-*")).first or raise "#{runtime} holds no runtime folder"
      assets = File.join(work, "assets")
      stage = File.join(work, "asset")
      FileUtils.mkdir_p([assets, File.join(stage, "app")])
      %w[lib libexec].each { |folder| FileUtils.cp_r(File.join(tree, folder), stage) }
      FileUtils.cp([File.join(Parity::PROBE, "main.rb"), File.join(FIXTURES, "app", "hello.rb")], File.join(stage, "app"))
      system("zip", "-q", "-r", "-0", "-X", File.join(assets, "fledge.zip"), "lib", "libexec", "app", chdir: stage, exception: true)
      apk = gradle(work, tree, assets)
      check(apk, out)
      FileUtils.cp(apk, File.join(work, "FledgeParity.apk"))
      out.puts "Built #{File.join(work, 'FledgeParity.apk')}"
      true
    end

    private_class_method def self.gradle(work, tree, assets)
      builder = RuntimeBuilder.new(platform: RuntimeBuilder.platform("android"))
      pins = builder.sources.fetch("mobile")
      zip = builder.fetch(pins.fetch("gradle").fetch("url"), pins.fetch("gradle").fetch("sha256"))
      home = File.join(work, "gradle-#{pins.fetch('gradle').fetch('version')}")
      system("unzip", "-q", "-o", zip, "-d", work, exception: true) unless File.directory?(home)
      project = File.join(work, "host")
      FileUtils.cp_r(File.join(FIXTURES, "android"), project)
      system(File.join(home, "bin", "gradle"), "--no-daemon", "--quiet", "--project-dir", project, "--project-cache-dir",
        File.join(work, "gradle-cache"), "assembleDebug", "-Pfledge.agp=#{pins.fetch('agp')}",
        "-Pfledge.aar=#{File.join(tree, 'FledgeRuby.aar')}", "-Pfledge.assets=#{assets}", "-Pfledge.buildDir=#{File.join(work, 'build')}",
        exception: true)
      Dir.glob(File.join(work, "build", "outputs", "apk", "debug", "*.apk")).first or raise "Gradle built no APK"
    end

    # Play's rules for what the app carries: every native library stored
    # aligned for 16 KB pages (zipalign -c -P 16), and API 36 targeted
    # (aapt2 dump badging), with the Android SDK's own build tools.
    private_class_method def self.check(apk, out)
      sdk = ENV["ANDROID_HOME"] || ENV["ANDROID_SDK_ROOT"] or raise "the check needs ANDROID_HOME, the Android SDK"
      tools = Dir.glob(File.join(sdk, "build-tools", "*")).max_by { |path| Gem::Version.new(File.basename(path)[/\A[\d.]+/]) }
      aligned, status = Open3.capture2e(File.join(tools, "zipalign"), "-c", "-P", "16", "-v", "4", apk)
      raise "#{apk} is not aligned for 16 KB pages:\n#{aligned}" unless status.success?

      out.puts aligned.lines.grep(/\.so|Verification/).join
      badging = Open3.capture2(File.join(tools, "aapt2"), "dump", "badging", apk).first
      raise "#{apk} does not target API 36" unless badging.include?("targetSdkVersion:'36'")

      out.puts badging.lines.grep(/sdkversion|native-code/i).join
    end

    def initialize(apk:, work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      @apk = File.expand_path(apk)
      @work = File.expand_path(work)
      @out = out
    end

    # Installs the app on the running emulator, runs both scripts, and
    # returns whether hello.rb said what it should and every difference
    # the probe found is justified.
    def call
      device = "#{adb('shell', 'getprop', 'ro.product.cpu.abi').strip} API #{adb('shell', 'getprop', 'ro.build.version.sdk').strip}, " \
        "#{adb('shell', 'getconf', 'PAGE_SIZE').strip}-byte pages"
      adb("install", "-r", @apk)
      adb("logcat", "-G", "16M")
      parity = MobileParity.new(target: "#{adb('shell', 'getprop', 'ro.product.cpu.abi').strip.sub('arm64-v8a', 'aarch64')}-linux-android",
        work: @work, out: @out)
      parity.check_hello(launch("hello.rb"), device)
      parity.compare(MobileParity.report(launch("main.rb")), device)
    end

    # Starts the app with +script+ after clearing logcat, and returns the
    # lines it logged up to Ruby's status, then stops it, since Ruby
    # boots once per process.
    private def launch(script)
      adb("logcat", "-c")
      adb("shell", "am", "start", "-W", "-n", "#{IDENTIFIER}/.MainActivity", "--es", "script", script)
      deadline = Time.now + TIMEOUT
      entries = logged
      until MobileParity.status(entries)
        raise "#{script} did not finish in #{TIMEOUT} seconds:\n#{entries.last(40).join("\n")}\n#{diagnosis}" if Time.now > deadline

        sleep 2
        entries = logged
      end
      sleep 3
      entries = logged
      adb("shell", "am", "force-stop", IDENTIFIER)
      @out.puts "#{script}: Ruby exited with status #{MobileParity.status(entries)}"
      raise "#{script} exited with status #{MobileParity.status(entries)}:\n#{entries.last(40).join("\n")}" unless MobileParity.status(entries).zero?

      entries
    end

    # What the emulator says of the host app, for a script that never
    # finished: whether its process runs, and logcat's last lines, of
    # every tag, where Android writes why an app did not start or died.
    private def diagnosis
      pid = Open3.capture2e("adb", "shell", "pidof", IDENTIFIER).first.strip
      logged = Open3.capture2e("adb", "logcat", "-d", "-t", "200").first
      File.write(File.join(@work, "logcat.txt"), logged)
      ["The host app's process: #{pid.empty? ? 'not running' : pid}", "logcat's last lines:", *logged.lines.last(120)].join("\n")
    end

    # What the app logged, one entry a line, as logcat -v raw prints it.
    private def logged
      adb("logcat", "-d", "-v", "raw", "-s", "#{IDENTIFIER}:V").lines.map(&:chomp).reject { |line| line.start_with?("--------- ") }
    end

    private def adb(*arguments)
      out, status = Open3.capture2("adb", *arguments)
      raise "adb #{arguments.join(' ')} failed:\n#{out}" unless status.success?

      out
    end
  end
end
