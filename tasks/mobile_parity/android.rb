# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"
require "open3"

class MobileParity
  # The check on an Android emulator: each app's Gradle project, as fledge
  # build android writes it, built with its own Gradle wrapper, debug and
  # unsigned release alike, as APKs and as the Android App Bundles Google
  # Play takes, and each APK checked for Play's 16 KB pages and target
  # API; each release bundle signed as a developer signs it for upload,
  # validated, and made into the split APKs Play would serve, which are
  # checked the same way and against Play's download limit
  # (doc/contributors/design/phone-projects.md, "The Android App Bundle check");
  # then, on the emulator CI's android-emulator-runner boots,
  # each app installed and started twice, from its debug APK with adb and
  # from its bundle's APKs with bundletool, its logcat read back each time.
  #
  # GitHub's Linux runners can emulate only x86_64, so the arm64-v8a
  # library is built and checked, but runs on no emulator here.
  class Android
    # How long an app may take, from launch to its status.
    TIMEOUT = 300

    # The host app's activity in every project fledge build writes.
    ACTIVITY = "org.setdef.fledge.host.MainActivity"

    # Where the built debug APKs go, one per app, named for its identifier,
    # each beside the APK set (+.apks+) bundletool made from its release
    # bundle.
    APKS = File.join(ROOT, "tmp", "mobile-parity", "android", "apks")

    # Play's limit on an app's base module, as a compressed download, in
    # bytes: "Base module: 500MB" ("Optimize your app's size and stay
    # within Google Play app size limits", support.google.com, answer
    # 9859372), read as the smaller of the two ways to count a megabyte.
    BASE_MODULE_LIMIT = 500_000_000

    # The throwaway upload key the check signs each bundle with, as a
    # developer signs theirs with their own: made anew in each check, and
    # never anyone's.
    KEY = { alias: "upload", password: "throwaway" }.freeze

    # Writes each app's project from the runtimes in +runtimes+, builds
    # each with Gradle, checks each APK and each release bundle, and keeps
    # each debug APK, and each release bundle's APK set, in APKS.
    def self.build(runtimes:, work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      FileUtils.rm_rf(work)
      FileUtils.mkdir_p(APKS)
      MobileParity.projects("android", runtimes:, out: File.join(work, "projects")).each do |app, project|
        gradlew = File.join(project, Gem.win_platform? ? "gradlew.bat" : "gradlew")
        system(gradlew, "--no-daemon", "--quiet", "--project-dir", project, "assembleDebug", "assembleRelease", "bundleDebug", "bundleRelease",
          exception: true)
        debug, release, bundle = built(app, project)
        [debug, release].each { |apk| check(apk, out) }
        FileUtils.cp(debug, File.join(APKS, "#{app.identifier}.apk"))
        check_bundle(bundle, apks: File.join(APKS, "#{app.identifier}.apks"), work: File.join(work, "bundles", app.identifier), out:)
        out.puts "Built #{app.name}: #{File.basename(debug)}, #{File.basename(release)}, and #{File.basename(bundle)}"
      end
      true
    end

    # What Gradle built of +app+ in +project+: its debug APK, its unsigned
    # release APK, and its release bundle, once its debug bundle is found
    # beside them too.
    def self.built(app, project)
      outputs = File.join(project, "build", "outputs")
      found = %w[apk/debug/*-debug.apk apk/release/*-release-unsigned.apk bundle/release/*-release.aab bundle/debug/*-debug.aab].map do |pattern|
        Dir.glob(File.join(outputs, pattern)).first or raise "Gradle built no #{pattern} of #{app.name}"
      end
      found.first(3)
    end

    # What bundletool dump config prints for a bundle whose APKs store
    # their native libraries, which the package installer then does not
    # extract: the plugin asks for it when useLegacyPackaging is false.
    # The template compresses them, so that Android extracts the ruby
    # program where an app may run it (ADR 069).
    UNCOMPRESSED_NATIVE_LIBRARIES = /"uncompressNativeLibraries":\s*\{[^}]*"enabled":\s*true/

    # Checks the release bundle +aab+ as Play would take it, in +work+:
    # signed with an upload key by jarsigner, as Android's documentation
    # signs a bundle from the command line, then validated by bundletool,
    # made into the APK set +apks+ that Play would serve, signed with the
    # same key, each of those APKs checked as Gradle's are, and their
    # largest download checked against BASE_MODULE_LIMIT.
    def self.check_bundle(aab, apks:, work:, out:)
      FileUtils.rm_rf(work)
      FileUtils.mkdir_p(work)
      key = File.join(work, "upload.jks")
      signing = ["-storepass", KEY[:password], "-keypass", KEY[:password]]
      jdk("keytool", "-genkeypair", "-keystore", key, *signing, "-alias", KEY[:alias], "-keyalg", "RSA", "-keysize", "2048", "-validity", "1",
        "-dname", "CN=Fledge throwaway upload key")
      signed = File.join(work, File.basename(aab))
      FileUtils.cp(aab, signed)
      jdk("jarsigner", "-keystore", key, *signing, signed, KEY[:alias])
      verified = jdk("jarsigner", "-verify", signed)
      raise "jarsigner did not verify #{signed}:\n#{verified}" unless verified.include?("jar verified.")

      bundletool("validate", "--bundle=#{signed}")
      config = bundletool("dump", "config", "--bundle=#{signed}")
      if config.match?(UNCOMPRESSED_NATIVE_LIBRARIES)
        raise "#{aab} asks for its native libraries stored, so Android would not extract the ruby program:\n#{config}"
      end

      bundletool("build-apks", "--bundle=#{signed}", "--output=#{apks}", "--overwrite", "--ks=#{key}", "--ks-pass=pass:#{KEY[:password]}",
        "--ks-key-alias=#{KEY[:alias]}", "--key-pass=pass:#{KEY[:password]}")
      check_splits(apks, work:, out:)
      size = download_size(bundletool("get-size", "total", "--apks=#{apks}"))
      raise "#{aab} downloads as #{size} bytes, above Play's #{BASE_MODULE_LIMIT} for a base module" if size > BASE_MODULE_LIMIT

      out.puts "#{File.basename(aab)}: #{File.size(aab)} bytes; its largest download, as bundletool measures it, #{size} bytes, " \
        "of Play's #{BASE_MODULE_LIMIT} for a base module"
    end

    # Checks every APK in the APK set +apks+, unpacked into +work+ with the
    # JDK's jar, which every computer that builds the project has: each
    # aligned for 16 KB pages with fledge.zip stored and its native
    # libraries compressed, and the base module's main APKs, one for each range of API
    # levels from API 26, each holding fledge.zip and targeting API 36.
    def self.check_splits(apks, work:, out:)
      into = File.join(work, "apks")
      FileUtils.mkdir_p(into)
      jdk("jar", "xf", File.expand_path(apks), chdir: into)
      splits = Dir.glob(File.join(into, "splits", "*.apk"))
      masters = splits.select { |split| File.basename(split).start_with?("base-master") }
      raise "#{apks} holds no base-master APK among #{splits.inspect}" if masters.empty?

      (splits - masters).each { |split| check(split, out, base: false) }
      lowest = masters.map { |master| check(master, out, from: nil) }.min
      raise "#{apks} has no base-master APK for API 26, but from API #{lowest}" unless lowest == 26

      out.puts "#{File.basename(apks)}: #{splits.map { |split| "#{File.basename(split)} (#{File.size(split)} bytes)" }.sort.join(', ')}"
    end

    # The largest download +sizes+ reports, from the CSV bundletool
    # get-size total prints, in bytes.
    def self.download_size(sizes)
      row = sizes.lines.map(&:strip).grep(/\A\d+,\d+\z/).first or raise "bundletool reported no size:\n#{sizes}"
      Integer(row.split(",").last)
    end

    # The entries zipalign's verbose lines, +aligned+, report packed as
    # Android does not take them, each with how it is packed: fledge.zip
    # compressed, which FledgeRuby unpacks straight from the APK and so
    # must be stored, and a native library stored, which the package
    # installer then does not extract where an app may run the ruby
    # program (ADR 069).
    def self.packed_wrongly(aligned)
      aligned.lines.filter_map do |line|
        name, compressed = line.match(/\A\s*\d+ (\S+) \(OK( - compressed)?\)\s*\z/)&.captures
        next unless name

        if name == "assets/fledge.zip" && compressed
          "#{name} (compressed)"
        elsif name.end_with?(".so") && !compressed
          "#{name} (stored)"
        end
      end
    end

    # Runs the JDK's +tool+ (java, keytool, jarsigner, or jar) from
    # JAVA_HOME, or from PATH without it, in +chdir+, and returns what it
    # printed.
    def self.jdk(tool, *arguments, chdir: Dir.pwd)
      home = ENV.fetch("JAVA_HOME", nil)
      command = home ? File.join(home, "bin", Fledge::Platform.local.executable(tool)) : tool
      printed, status = Open3.capture2e(command, *arguments, chdir:)
      raise "#{tool} #{arguments.join(' ')} failed:\n#{printed}" unless status.success?

      printed
    end

    # Runs bundletool, the jar BUNDLETOOL names (runtime/sources.yml pins
    # it, and CI fetches it), and returns what it printed.
    def self.bundletool(*)
      jar = ENV["BUNDLETOOL"] or raise "the check needs BUNDLETOOL, the path to bundletool's jar"
      jdk("java", "-jar", jar, *)
    end

    # Play's rules for what the app carries: every stored entry aligned
    # for 16 KB pages (zipalign -c -P 16), fledge.zip stored, and every
    # native library compressed, so that the installer extracts it,
    # which zipalign passes either way (#packed_wrongly); and,
    # unless +base+ is false, as for a split APK that holds one ABI's
    # libraries, fledge.zip there and API 36 targeted (aapt2 dump
    # badging), from API +from+ unless that is nil, as for a split APK
    # bundletool made for later APIs alone; with the Android SDK's own
    # build tools. Returns the lowest API the APK runs on, or nil when
    # +base+ is false.
    def self.check(apk, out, base: true, from: 26)
      sdk = ENV["ANDROID_HOME"] || ENV["ANDROID_SDK_ROOT"] or raise "the check needs ANDROID_HOME, the Android SDK"
      tools = build_tools(sdk)
      host = Fledge::Platform.local
      aligned, status = Open3.capture2e(File.join(tools, host.executable("zipalign")), "-c", "-P", "16", "-v", "4", apk)
      raise "#{apk} is not aligned for 16 KB pages:\n#{aligned}" unless status.success?

      wrong = packed_wrongly(aligned)
      raise "#{apk} packs what Android needs otherwise: #{wrong.join(', ')}" unless wrong.empty?

      out.puts aligned.lines.grep(/\.so|fledge\.zip|Verification/).join
      return unless base
      raise "#{apk} holds no stored assets/fledge.zip" unless aligned.match?(%r{ assets/fledge\.zip \(OK\)\r?$})

      badging = Open3.capture2(File.join(tools, host.executable("aapt2")), "dump", "badging", apk).first
      lowest = badging[/^minSdkVersion:'(\d+)'\r?$/, 1]&.to_i
      if !badging.include?("targetSdkVersion:'36'") || lowest.nil? || (from && lowest != from)
        raise "#{apk} does not target API 36 from API #{from || 26} or later:\n#{badging}"
      end

      out.puts badging.lines.grep(/\Apackage:|sdkversion|native-code|application-label:/i).join
      lowest
    end

    # The newest of the build tools in the Android SDK at +sdk+. The path
    # is made plain first: on Windows, ANDROID_HOME has backslashes, which
    # Dir.glob reads as escapes, and File.expand_path turns into slashes.
    def self.build_tools(sdk)
      Dir.glob(File.join(File.expand_path(sdk), "build-tools", "*"))
        .max_by { |path| Gem::Version.new(File.basename(path)[/\A[\d.]+/]) } or raise "#{sdk} has no build tools"
    end

    def initialize(work: File.join(ROOT, "tmp", "mobile-parity", "android"), out: $stdout)
      @work = File.expand_path(work)
      @out = out
    end

    # Installs each app on the running emulator and runs it, from its debug
    # APK and then from the APKs bundletool made for this device from its
    # release bundle, as Play would install them, and returns whether every
    # app printed what it should each time and every difference the probe
    # found is justified.
    def call
      adb("logcat", "-G", "16M")
      parity = MobileParity.new(target:, work: @work, out: @out)
      APPS.flat_map do |app|
        adb("install", "-r", File.join(APKS, "#{app.identifier}.apk"))
        from_apk = parity.check(app, launch(app), "#{device}, from its debug APK")
        # The bundle's APKs are signed with another key than the debug
        # APK, which Android refuses to install over it.
        adb("uninstall", app.identifier)
        Android.bundletool("install-apks", "--apks=#{File.join(APKS, "#{app.identifier}.apks")}")
        [from_apk, parity.check(app, launch(app), "#{device}, from its release bundle")]
      end.all?
    end

    # The platform of the running emulator, as Parity::JUSTIFIED and
    # RubySpec::JUSTIFIED name it.
    def target
      "#{abi.sub('arm64-v8a', 'aarch64')}-linux-android"
    end

    # The running emulator, described: its ABI, API level, page size, and
    # memory.
    def device
      @device ||= device_description
    end

    private def device_description
      memory = adb("shell", "cat", "/proc/meminfo")[/\AMemTotal:\s+(\d+) kB/, 1].to_i / 1024
      "#{abi} API #{adb('shell', 'getprop', 'ro.build.version.sdk').strip}, #{adb('shell', 'getconf', 'PAGE_SIZE').strip}-byte pages, " \
        "#{memory} MB of memory"
    end

    # The messages logged under +tag+ in +log+, what logcat -v tag
    # prints ("I/tag: message", the tag padded to eight characters, as
    # logprint.cpp's android_log_formatLogLine writes it), in order,
    # without those of standard error unless +standard_error+. The
    # embedding API logs what Ruby writes to standard error as warnings
    # and standard output as information, as the host logs its own lines
    # (runtime/mobile/android.c, fledge_log_write), each stream read by a
    # thread of its own, so logcat holds each stream's lines in order but
    # the two interleaved as those threads happen to run
    # (doc/contributors/design/phone-runtimes.md, "Output to the system
    # log").
    def self.messages(log, tag, standard_error: true)
      entry = %r{\A([VDIWEF])/#{Regexp.escape(tag)} *: ?(.*)\z}
      log.each_line(chomp: true).filter_map do |line|
        priority, message = line.match(entry)&.captures
        message if priority && (standard_error || priority != "W")
      end
    end

    # Starts +app+ after clearing logcat, and returns what it logged
    # (Logged) up to its status and after, until the log settles, then
    # stops it, since Ruby boots once per process. It fails, reporting
    # both streams, when the app has not finished in +timeout+ seconds,
    # or when its process has ended without the host's status, as when
    # Android stopped it.
    def launch(app, timeout: TIMEOUT)
      adb("logcat", "-c")
      adb("shell", "am", "start", "-W", "-n", "#{app.identifier}/#{ACTIVITY}")
      deadline = Time.now + timeout
      until MobileParity.status(logged(app).entries)
        ended = !running?(app) && !MobileParity.status(logged(app).entries)
        if ended || Time.now > deadline
          why = ended ? "ended without a status" : "did not finish in #{timeout} seconds"
          raise "#{app.name} #{why}:\n#{logged(app).entries.last(40).join("\n")}\n#{diagnosis(app)}"
        end

        sleep 2
      end
      MobileParity.settled { logged(app) }.tap { adb("shell", "am", "force-stop", app.identifier) }
    end

    # What the emulator says of +app+, for one that never finished:
    # whether its process runs, and what logcat holds of it since its
    # launch cleared the log, kept whole for the job's artifact: the lines
    # that name it, those its processes logged, by the process IDs
    # ActivityManager gave them, and those of Android's crash reporters,
    # where Android writes why an app did not start or died.
    private def diagnosis(app)
      pid = Open3.capture2e("adb", "shell", "pidof", app.identifier).first.strip
      everything = Open3.capture2e("adb", "logcat", "-d", "-v", "threadtime").first
      File.write(File.join(@work, "logcat-#{app.identifier}.txt"), everything)
      [
        "The app's process: #{pid.empty? ? 'not running' : pid}",
        "What logcat says of it:",
        *MobileParity::Android.about(app, everything).last(150),
      ].join("\n")
    end

    # The lines of +log+, logcat's threadtime format, about +app+: those
    # that name it, those of its processes, and those of the crash
    # reporters (DEBUG, AndroidRuntime, libc).
    def self.about(app, log)
      started = log.scan(%r{Start proc (\d+):#{Regexp.escape(app.identifier)}[/:]}).flatten
      log.lines.map(&:chomp).select do |line|
        fields = line.split(" ", 6)
        line.include?(app.identifier) || started.include?(fields[2]) || %w[DEBUG AndroidRuntime libc].include?(fields[5]&.split(":")&.first&.strip)
      end
    end

    # What +app+ logged under its identifier, as Android.messages reads
    # it.
    private def logged(app)
      log = adb("logcat", "-d", "-v", "tag", "-s", "#{app.identifier}:V")
      Logged.new(entries: Android.messages(log, app.identifier), output: Android.messages(log, app.identifier, standard_error: false))
    end

    private def running?(app)
      !Open3.capture2e("adb", "shell", "pidof", app.identifier).first.strip.empty?
    end

    private def abi
      @abi ||= adb("shell", "getprop", "ro.product.cpu.abi").strip
    end

    private def adb(*arguments)
      out, status = Open3.capture2("adb", *arguments)
      raise "adb #{arguments.join(' ')} failed:\n#{out}" unless status.success?

      out
    end
  end
end
