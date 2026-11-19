# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require_relative "test_helper"
require_relative "../tasks/mobile_parity"

# The parts of the mobile check (doc/contributors/design/phone-projects.md,
# "Parity on a phone") that need no simulator or emulator: reading the
# probe's report and an app's status back from the entries of a system
# log, the apps it builds, the reference Ruby's environment, and the
# justifications for what a phone does differently.
# test/integration/mobile_parity_projects_test.rb has fledge build make
# the apps' projects, and CI's Mobile apps jobs build the apps with
# fledge build and run them in the iOS Simulator and Android emulators.
class MobileParityTest < Minitest::Test
  # The embedding API sends a line longer than a log entry holds as
  # several entries in a row, so the report is the entries from its
  # first, joined, up to where they make a JSON object, but for the
  # host's status line, which its thread may log among them.
  def test_reads_the_report_from_the_log_entries_it_was_split_into
    json = JSON.generate({ "ARGV" => [], "long" => "é" * 900 })
    entries = ["booting", "FLEDGE-PARITY #{json[0, 700]}", json[700, 1000], "Parity exited with status 0", json[1700..]]

    assert_equal JSON.parse(json), MobileParity.report(entries)
  end

  # A line of standard error, which the embedding API logs from a thread
  # of its own, can land inside the report, so the report is read from
  # standard output alone while a failure still shows both streams.
  def test_reads_the_report_from_standard_output_when_standard_error_lands_inside_it
    json = JSON.generate({ "ARGV" => [], "long" => "é" * 900 })
    ndjson = [
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "FLEDGE-PARITY #{json[0, 700]}" },
      { "processID" => 7, "messageType" => "Error", "eventMessage" => "warning: something on standard error" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => json[700..] },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "Parity exited with status 0" },
    ].map { |entry| JSON.generate(entry) }.join("\n")
    logged = MobileParity::Logged.new(entries: MobileParity::IOS.messages(ndjson, 7),
      output: MobileParity::IOS.messages(ndjson, 7, standard_error: false))

    refute_equal JSON.parse(json), MobileParity.report(logged.entries)
    assert_equal JSON.parse(json), MobileParity.report(logged.output)
    assert_includes logged.entries, "warning: something on standard error"
  end

  def test_a_log_without_a_whole_report_fails
    assert_raises(RuntimeError) { MobileParity.report(["FLEDGE-PARITY {\"ARGV\":"]) }
    assert_raises(RuntimeError) { MobileParity.report(["nothing here"]) }
  end

  # The host app of every project fledge build writes logs the app's
  # exit status when its program ends
  # (doc/contributors/design/phone-projects.md, "The host app").
  def test_the_status_is_the_hosts_last_word
    assert_equal 0, MobileParity.status(["a", "Mobile App exited with status 0"])
    assert_equal 1, MobileParity.status(["Hello exited with status 1"])
    assert_nil MobileParity.status(["a", "exited with status 0"])
  end

  # What Ruby printed last may reach the log after the host's status, so
  # the log is read until it stops growing, or until the limit.
  def test_the_log_is_read_until_it_settles
    reads = [["status"], ["status", "a"], ["status", "a", "b"], ["status", "a", "b"]]
    assert_equal ["status", "a", "b"], MobileParity.settled(interval: 0) { reads.shift }
    assert_empty reads

    growing = Enumerator.new { |lines| (1..).each { |n| lines << n } }
    assert_operator MobileParity.settled(interval: 0.01, limit: 0.05) { growing.next }, :>, 1
  end

  # Each app the check builds names itself as its fledge.yml does, so its
  # project, scheme, and log are found by those names.
  def test_each_app_is_named_as_its_fledge_yml_names_it
    MobileParity::APPS.each do |app|
      built = Fledge::App.at(File.join(MobileParity::ROOT, app.path))
      assert_equal [app.name, app.identifier], [built.name, built.identity.identifier], app.path
    end
  end

  # Fledge's own manifest gives the reasons the check expects, and a
  # manifest that names a category with another reason fails it.
  def test_the_privacy_manifest_check_compares_reasons
    skip "plutil is Apple's" unless RUBY_PLATFORM.include?("darwin")
    template = File.join(MobileParity::ROOT, "lib", "fledge", "templates", "ios", "Host", "PrivacyInfo.xcprivacy")
    manifest = JSON.parse(IO.popen(["plutil", "-convert", "json", "-o", "-", template], &:read))

    assert_empty MobileParity::IOS.wrong_reasons(manifest)

    first = manifest["NSPrivacyAccessedAPITypes"].first
    first["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1"]

    assert_equal({ first["NSPrivacyAccessedAPIType"] => ["DDA9.1"] }, MobileParity::IOS.wrong_reasons(manifest))

    first["NSPrivacyAccessedAPITypeReasons"] = ["DDA9.1", "C617.1"]

    assert_empty MobileParity::IOS.wrong_reasons(manifest)
  end

  # The reference runs as a person runs ruby main.rb: in a UTF-8 locale,
  # with a home folder of its own and nothing of the runner's Ruby.
  def test_the_reference_runs_with_a_persons_plain_environment
    env = MobileParity.reference_environment("/work", "C.UTF-8", { "PATH" => "/bin", "RUBYOPT" => "-W0", "GEM_HOME" => "/g", "CI" => "true" })

    assert_equal({ "PATH" => "/bin", "HOME" => "/work/home", "LANG" => "C.UTF-8" }, env)
  end

  # Each charmap is what Ruby's Encoding.locale_charmap is under that
  # LANG: glibc reads a locale it lacks as C, ANSI_X3.4-1968, and macOS
  # reads it as US-ASCII.
  GLIBC_WITH_EN_US = { "en_US.UTF-8" => "UTF-8", "C.UTF-8" => "UTF-8", "C.utf8" => "UTF-8", "UTF-8" => "ANSI_X3.4-1968" }.freeze
  STOCK_UBUNTU = GLIBC_WITH_EN_US.merge("en_US.UTF-8" => "ANSI_X3.4-1968").freeze
  MACOS = { "en_US.UTF-8" => "UTF-8", "C.UTF-8" => "UTF-8", "C.utf8" => "US-ASCII", "UTF-8" => "UTF-8" }.freeze

  # The reference keeps en_US.UTF-8 where the computer has it, and on a
  # stock Ubuntu, which has only C and C.UTF-8, takes C.UTF-8 rather than
  # running in the C locale, whose ASCII the check would blame on the
  # phone.
  def test_the_reference_takes_the_first_utf8_locale_the_computer_has
    assert_equal "en_US.UTF-8", MobileParity.reference_locale("ruby", &GLIBC_WITH_EN_US.method(:fetch))
    assert_equal "en_US.UTF-8", MobileParity.reference_locale("ruby", &MACOS.method(:fetch))
    assert_equal "C.UTF-8", MobileParity.reference_locale("ruby", &STOCK_UBUNTU.method(:fetch))
    assert_equal "C.utf8", MobileParity.reference_locale("ruby") { |name| (name == "C.utf8") ? "utf-8" : "US-ASCII" }
  end

  # With no UTF-8 locale at all, the check stops and says what is
  # missing, rather than report the C locale as the phone's difference.
  def test_the_reference_stops_on_a_computer_with_no_utf8_locale
    error = assert_raises(RuntimeError) { MobileParity.reference_locale("/r/ruby") { "ANSI_X3.4-1968" } }

    assert_includes error.message, "no UTF-8 locale"
    assert_includes error.message, "LANG=en_US.UTF-8, C.UTF-8, C.utf8, UTF-8"
  end

  # A phone starts an app with an environment of its own, so the check
  # compares the app's ENV, and a child's, with the one the system gave
  # it, which its host logged, not with the desktop's: a variable Fledge
  # adds fails, but for the HOME Android gives no app, which FledgeRuby
  # sets.
  def test_a_phones_env_is_compared_with_the_environment_the_system_gave_the_app
    paths = { "app" => "/data/app", "prefix" => "/data/ruby", "home" => "/data/files" }
    reference = { "paths" => { "app" => "/w/app", "prefix" => "/w/ruby", "home" => "/w/home" }, "ENV" => { "PATH" => "/bin", "LANG" => "C" } }
    given = { "PATH" => "/system/bin", "TMPDIR" => "/data/cache" }
    app = -> (env) { { "paths" => paths, "ENV" => env, "child ENV" => env } }
    differences = -> (target, env) { MobileParity.differences(reference, app.call(env), given, platform: target, work: "/w") }

    %w[arm64-ios-simulator x86_64-linux-android].each do |target|
      assert_empty differences.call(target, given), target
      certificates = differences.call(target, given.merge("SSL_CERT_FILE" => "/data/ruby/libexec/cert.pem"))
      assert_equal ["ENV", "child ENV"], certificates.map(&:fact), target
      refute certificates.any?(&:justified?), target
    end
    home = given.merge("HOME" => "/data/files")
    assert differences.call("x86_64-linux-android", home).all?(&:justified?)
    refute differences.call("arm64-ios-simulator", home).any?(&:justified?)
  end

  # The probe's host logs the environment the system gave it, a line
  # for each variable, before it starts Ruby: the host fledge build
  # writes, with one loop more, which the check reads back.
  def test_the_probes_host_logs_the_environment_it_was_given
    MobileParity::Environment::HOSTS.each do |phone, (file, _, loop)|
      Dir.mktmpdir do |project|
        template = File.join(MobileParity::ROOT, "lib", "fledge", "templates", phone, file)
        FileUtils.mkdir_p(File.dirname(File.join(project, file)))
        FileUtils.cp(template, File.join(project, file))

        MobileParity::Environment.record(phone, project)
        host = File.read(File.join(project, file))

        assert_includes host, loop, phone
        assert_operator host.index(loop), :<, host.index((phone == "ios") ? "= fledge_ruby_run_app(" : "FledgeRuby.startApp("), phone
        File.write(File.join(project, file), "")
        assert_raises(RuntimeError, phone) { MobileParity::Environment.record(phone, project) }
      end
    end
    entries = ["FLEDGE-ENVIRON PATH=/system/bin", "booting", "FLEDGE-ENVIRON EMPTY=", "FLEDGE-ENVIRON A=b=c"]
    assert_equal({ "PATH" => "/system/bin", "EMPTY" => "", "A" => "b=c" }, MobileParity::Environment.read(entries))
    assert_raises(RuntimeError) { MobileParity::Environment.read(["booting"]) }
  end

  # The Android SDK's newest build tools, found from ANDROID_HOME as the
  # runner sets it: with Windows's separators on Windows, which Dir.glob
  # reads as escapes, so the check finds them from the path made plain.
  # The SDK's folder is named by its long names, as Dir.glob names what
  # it finds (Fledge::LongPath), where Windows' TMP gives an 8.3 name.
  def test_the_build_tools_are_the_sdks_newest_wherever_its_path_comes_from
    Dir.mktmpdir do |folder|
      sdk = Fledge::LongPath.of(folder)
      %w[35.0.0 36.1.0 36.0.0].each { |version| FileUtils.mkdir_p(File.join(sdk, "build-tools", version)) }
      native = File::ALT_SEPARATOR ? File.expand_path(sdk).tr("/", File::ALT_SEPARATOR) : sdk

      assert_equal File.join(File.expand_path(sdk), "build-tools", "36.1.0"), MobileParity::Android.build_tools(native)
    end
    assert_raises(RuntimeError) { MobileParity::Android.build_tools(File.join(Dir.tmpdir, "no-sdk-here")) }
  end

  # zipalign -c -P 16 passes an entry whether it is stored or compressed,
  # so the check reads its verbose lines for how each entry Android needs
  # a certain way is packed: the asset fledge.zip stored, which
  # FledgeRuby unpacks from the APK, and every native library
  # compressed, which only the package installer's extraction puts where
  # Android lets an app run its ruby program (doc/contributors/design/phone-runtimes.md,
  # "The ruby program on Android").
  def test_what_zipalign_finds_packed_as_android_does_not_take_it
    aligned = <<~ALIGNED
      Verifying alignment of base-master.apk (4)...
            49 AndroidManifest.xml (OK - compressed)
          1332 assets/fledge.zip (OK - compressed)
      30261325 classes.dex (OK - compressed)
         16384 lib/x86_64/libfledgeruby.so (OK)
      16416768 lib/x86_64/libfledgerubyexe.so (OK - compressed)
      Verification succesful
    ALIGNED

    assert_equal ["assets/fledge.zip (compressed)", "lib/x86_64/libfledgeruby.so (stored)"], MobileParity::Android.packed_wrongly(aligned)
    assert_empty MobileParity::Android.packed_wrongly(aligned.sub("fledge.zip (OK - compressed)", "fledge.zip (OK)")
      .sub("libfledgeruby.so (OK)", "libfledgeruby.so (OK - compressed)"))
  end

  # bundletool get-size total prints the smallest and largest download
  # of the APKs it made, as CSV, in bytes; Play's limit is on the largest.
  def test_the_download_size_is_the_largest_bundletool_reports
    assert_equal 17_290_310, MobileParity::Android.download_size("MIN,MAX\n17112131,17290310\n")
    assert_raises(RuntimeError) { MobileParity::Android.download_size("nothing") }
  end

  # A Gradle build that failed is reported by what Gradle's --info log
  # says of each repository's answers, a 404 as "Resource missing" and
  # any other refusal with its status, then by Gradle's own failure, so
  # that a "Could not find" shows which answer it stood for.
  def test_a_failed_gradle_build_is_reported_by_its_repositories_answers_and_its_failure
    log = <<~LOG
      Initialized native services in: /home/runner/.gradle/native
      Resource missing. [HTTP GET: https://dl.google.com/dl/android/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Resource missing. [HTTP GET: https://repo.maven.apache.org/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Failed to get resource: GET. [HTTP 429: https://repo.maven.apache.org/maven2/org/ow2/asm/asm/9.9/asm-9.9.pom)]
      Resolve mutations for :app:compileJava (Thread[included builds,5,main]) started.

      FAILURE: Build failed with an exception.

      * What went wrong:
         > Could not find com.google.guava:guava:33.4.0-jre.

      BUILD FAILED in 9s
      Watched directory hierarchies: []
    LOG

    assert_equal <<~REPORT.chomp, MobileParity::Android.gradle_failure(log)
      Resource missing. [HTTP GET: https://dl.google.com/dl/android/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Resource missing. [HTTP GET: https://repo.maven.apache.org/maven2/com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.pom]
      Failed to get resource: GET. [HTTP 429: https://repo.maven.apache.org/maven2/org/ow2/asm/asm/9.9/asm-9.9.pom)]
      FAILURE: Build failed with an exception.

      * What went wrong:
         > Could not find com.google.guava:guava:33.4.0-jre.

      BUILD FAILED in 9s
    REPORT
  end

  # An app that never finished is diagnosed from logcat's lines about it:
  # those naming it, those of its process, by the ID ActivityManager
  # started it with, and the crash reporters', not the system's chatter.
  def test_an_unfinished_apps_diagnosis_is_what_logcat_says_of_it
    app = MobileParity::APPS.fetch(1)
    log = <<~LOG
      11-01 05:26:40.100   745   859 I ActivityManager: Start proc 8123:com.setdef.fledge.MobileApp/u0a213 for next-top-activity {com.setdef.fledge.MobileApp/org.setdef.fledge.host.MainActivity}
      11-01 05:26:40.300   745  1024 D WifiScoreCard: txRate: 1 txSpeed: 11
      11-01 05:26:41.000  8123  8140 F libc    : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR) in tid 8140 (ruby)
      11-01 05:26:41.200  8150  8150 F DEBUG   : pid: 8123, tid: 8140, name: ruby  >>> com.setdef.fledge.MobileApp <<<
      11-01 05:26:41.300  8150  8150 F DEBUG   :       #00 pc 0000000000123456  libfledgeruby.so
      11-01 05:26:41.400  8123  8123 W setdef.fledge.MobileAp: something of its own
      11-01 05:26:42.000  9000  9000 I chatty  : uid=1000 expire 3 lines
    LOG

    lines = MobileParity::Android.about(app, log)

    assert_equal [0, 2, 3, 4, 5], lines.map { |line| log.lines.map(&:chomp).index(line) }
  end

  # An app that sets $0 changes the command line pidof finds it by, so
  # the harness follows the process ActivityManager says it started.
  def test_an_apps_process_is_the_one_activity_manager_started_for_it
    app = MobileParity::APPS.fetch(1)
    log = <<~LOG
      11-01 05:26:40.100   745   859 I ActivityManager: Start proc 8123:com.setdef.fledge.MobileApp/u0a213 for next-top-activity {com.setdef.fledge.MobileApp/org.setdef.fledge.host.MainActivity}
      11-01 05:26:40.200   745   859 I ActivityManager: Start proc 8200:com.setdef.fledge.MobileAppOther/u0a214 for service {}
      11-01 05:26:44.100   745   859 I ActivityManager: Start proc 8301:com.setdef.fledge.MobileApp:worker/u0a213 for service {}
    LOG

    assert_equal %w[8123 8301], MobileParity::Android.started(app, log)
    assert_empty MobileParity::Android.started(app, "11-01 05:26:40.300   745  1024 D WifiScoreCard: txRate: 1\n")
  end

  # An emulator, as MobileParity::Android#launch sees it through adb,
  # that moves on a step each time the app's log is read: the app's
  # process appears, to logcat and to pidof, from step +started+, ends
  # at step +ends+, and logs the host's status from step +finishes+,
  # each nil for never.
  class Emulator < MobileParity::Android
    PID = "4242"

    def initialize(app, work:, started: 0, ends: nil, finishes: nil)
      super(work:, out: StringIO.new)
      @app = app
      @started = started
      @ends = ends
      @finishes = finishes
      @step = 0
    end

    private def adb(*arguments)
      case arguments
      in ["logcat", "-d", "-v", "threadtime"] then whole_log
      in ["logcat", "-d", "-v", "tag", "-s", _] then tagged.tap { @step += 1 }
      else ""
      end
    end

    private def whole_log
      return "" unless started?

      "11-19 06:00:00.100   748   781 I ActivityManager: Start proc #{PID}:#{@app.identifier}/u0a213 for next-top-activity " \
        "{#{@app.identifier}/#{ACTIVITY}}\n"
    end

    private def tagged
      lines = ["I/#{@app.identifier}: running"]
      lines << "I/#{@app.identifier}: #{@app.name} exited with status 0" if @finishes && @step >= @finishes
      "#{lines.join("\n")}\n"
    end

    private def pidof(_app) = (PID if running?(PID))

    private def running?(pid) = pid == PID && started? && !(@ends && @step >= @ends)

    private def started? = !@started.nil? && @step >= @started
  end

  # Logcat holds a line a moment after it is logged, and am start -W can
  # return before ActivityManager has started the process, so a launch
  # that finds no process at first looks again while it waits; on
  # 2026-11-16 the ruby/spec job took a process it had not yet seen for
  # one that had ended.
  def test_a_launch_waits_for_a_process_it_has_not_yet_seen
    app = MobileParity::APPS.fetch(1)
    Dir.mktmpdir do |work|
      logged = Emulator.new(app, work:, started: 1, finishes: 3).launch(app, timeout: 60, interval: 0)

      assert_equal 0, MobileParity.status(logged.entries)
    end
  end

  # A process that was seen and is gone without the host's status has
  # ended, as when Android stopped it; one never seen has not finished.
  def test_a_launch_fails_for_a_process_that_ended_and_one_never_seen
    app = MobileParity::APPS.fetch(1)
    Dir.mktmpdir do |work|
      ended = assert_raises(RuntimeError) { Emulator.new(app, work:, ends: 2).launch(app, timeout: 60, interval: 0) }
      unseen = assert_raises(RuntimeError) { Emulator.new(app, work:, started: nil).launch(app, timeout: 0, interval: 0) }

      assert_match(/\AMobile App ended without a status:/, ended.message)
      assert_match(/\AMobile App did not finish in 0 seconds:/, unseen.message)
    end
  end

  # The embedding API logs standard error as errors on iOS, and standard
  # output and the host's lines as default messages, so a reader that
  # wants one stream in its own order can leave the other out; lines of
  # other processes, and what is not JSON, are not the app's.
  def test_ios_messages_are_the_processes_own_and_may_leave_out_standard_error
    ndjson = [
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "1)" },
      { "processID" => 7, "messageType" => "Error", "eventMessage" => "The rubyspec temp directory is not empty." },
      { "processID" => 8, "messageType" => "Default", "eventMessage" => "another launch" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "core: Class#initialize is not defined FAILED" },
      { "processID" => 7, "messageType" => "Default", "eventMessage" => "RubySpec exited with status 1" },
    ].map { |entry| JSON.generate(entry) }.push("Filtering the log data using ...").join("\n")

    assert_equal [
      "1)",
      "The rubyspec temp directory is not empty.",
      "core: Class#initialize is not defined FAILED",
      "RubySpec exited with status 1",
], MobileParity::IOS.messages(ndjson, 7)
    assert_equal ["1)", "core: Class#initialize is not defined FAILED", "RubySpec exited with status 1"],
      MobileParity::IOS.messages(ndjson, 7, standard_error: false)
  end

  # On Android the embedding API logs standard error as warnings and
  # standard output as information, as the host logs its status, which
  # logcat -v tag prints before each message, an empty one included.
  def test_android_messages_are_the_tags_own_and_may_leave_out_standard_error
    tag = "com.setdef.fledge.RubySpec"
    log = <<~LOG
      --------- beginning of main
      I/#{tag}: 1)
      W/#{tag}: The rubyspec temp directory is not empty.
      I/#{tag}:#{' '}
      I/#{tag}:   indented
      I/#{tag}: core: Class#initialize is not defined FAILED
      I/OtherTag: not the app's
      I/#{tag}: RubySpec exited with status 1
    LOG

    assert_equal [
      "1)",
      "The rubyspec temp directory is not empty.",
      "",
      "  indented",
      "core: Class#initialize is not defined FAILED",
      "RubySpec exited with status 1",
], MobileParity::Android.messages(log, tag)
    assert_equal ["1)", "", "  indented", "core: Class#initialize is not defined FAILED", "RubySpec exited with status 1"],
      MobileParity::Android.messages(log, tag, standard_error: false)
  end
end
